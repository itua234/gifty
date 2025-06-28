// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "./PriceConverter.sol";
using PriceConverter for uint256;

/**
 * @title GiftCard
 * @dev A smart contract for creating and claiming decentralized gift cards.
 * Users can create gift cards with an associated Ether value and a PIN code.
 * The receiver can claim the Ether by providing the correct PIN.
*/
contract GiftCard {
    error GiftCardNotFound(uint256 cardId);
    error NotAuthorized(address caller);
    error AlreadyClaimedOrRefunded(uint256 cardId);
    error InvalidPin(uint256 cardId);
    error IncorrectValue(uint256 expected, uint256 received);
    error CardLocked(uint256 unlockTimestamp);
    error InvalidReceiver(address receiver);
    error ZeroValueNotAllowed();
    error CardNotExpired(uint256 expireAt);
    error TransferFailed();
    error InvalidPhoneNumber();

    struct Card {
        uint256 cardId;
        address payable creator;
        address payable receiver; 
        uint256 value;
        bytes32 pinHash;
        bool claimed;
        uint256 createdAt;
        uint256 expireAt;
    }

    AggregatorV3Interface private s_priceFeed;
    mapping(uint256 => Card) public giftCards;
    uint256 private nextCardId;

    uint256 private s_totalFeesCollected; // Total fees collected from gift card transactions
    uint256 private s_claimFee; // e.g., 2 for 0.02%
    address payable private s_feeCollector; // Address to send the fee to

    enum ClaimType { Token, Bank, Airtime, Data }

    event GiftCardCreated(
        uint256 indexed cardId,
        address indexed creator,
        address indexed receiver,
        uint256 value,
        uint256 createdAt
    );
    event GiftCardClaimed(
        uint256 indexed cardId,
        address indexed receiver,
        uint256 value,
        uint256 createdAt
    );
    event BankClaimRequested(
        uint256 indexed cardId,
        address indexed claimer,
        string bankAccount,
        string bankCode,
        uint256 usdAmount,
        uint256 ethAmount,
        uint256 timestamp
    );
    event AirtimeClaimRequested(
        uint256 indexed cardId,
        address indexed claimer,
        string phoneNumber, // E.g., "+2348012345678"
        uint256 usdAmount,   // Amount in USD after conversion, for the off-chain service
        uint256 ethAmount,   // Original ETH amount for reference
        uint256 timestamp
    );
    event FeeCollected(address indexed collector, uint256 fee);

    constructor(address priceFeed) {
        nextCardId = 1;
        s_priceFeed = AggregatorV3Interface(priceFeed);
        s_feeCollector = payable(msg.sender);
        s_claimFee = 5;
    }

    modifier onlyOwner() {
        if (msg.sender != s_feeCollector) {
            revert NotAuthorized(msg.sender);
        }
        _;
    }

    modifier onlyCardCreator(uint256 _cardId) {
        if (giftCards[_cardId].creator != msg.sender) {
            revert NotAuthorized(msg.sender);
        }
        _;
    }

    function createGiftCard(uint256 _expireAt, string memory pin) public payable {
        if(msg.value == 0) revert ZeroValueNotAllowed();
        if(msg.sender == address(0)) revert NotAuthorized(msg.sender);

        uint256 cardId = nextCardId;
        bytes32 pinHash = keccak256(abi.encodePacked(pin));

        giftCards[cardId] = Card({
            cardId: cardId,
            creator: payable(msg.sender),
            receiver: payable(address(0)),
            value: msg.value,
            pinHash: pinHash,
            claimed: false,
            createdAt: block.timestamp,
            expireAt: _expireAt
        });

        nextCardId++;

        emit GiftCardCreated(
            cardId,
            msg.sender,
            address(0),
            msg.value,
            block.timestamp
        );
    }

    /**
     * @dev Allows anyone to view the details of a gift card (excluding the PIN code).
     * This function is `view` as it does not modify the state of the blockchain.
     * @param _cardId The unique identifier of the gift card.
     * @return cardId The unique ID of the card.
     * @return creator The address of the card's creator.
     * @return receiver The address of the card's receiver.
     * @return value The Ether value of the card.
     * @return claimed True if the card has been claimed, false otherwise.
     * @return createdAt The timestamp when the card was created.
     * @return expireAt The timestamp when the card expires.
    */
    function getGiftCardDetails(uint256 _cardId)
        public
        view
        returns (
            uint256 cardId,
            address creator,
            address receiver,
            uint256 value,
            bool claimed,
            uint256 createdAt,
            uint256 expireAt
        )
    {
        Card storage card = giftCards[_cardId];
        if(card.cardId == 0) revert GiftCardNotFound(_cardId);

        return (
            card.cardId,
            card.creator,
            card.receiver,
            card.value,
            card.claimed,
            card.createdAt,
            card.expireAt
        );
    }

    function reclaimExpiredCard(uint256 _cardId, string memory pin) 
        external 
        onlyCardCreator(_cardId) 
    {
        Card storage card = giftCards[_cardId];

        if(card.cardId == 0) revert GiftCardNotFound(_cardId);
        if (card.claimed) revert AlreadyClaimedOrRefunded(_cardId);
        if (block.timestamp < card.expireAt) revert CardNotExpired(card.expireAt);
        if (card.value == 0) revert AlreadyClaimedOrRefunded(_cardId);

        if(card.pinHash != keccak256(abi.encodePacked(pin))) revert InvalidPin(_cardId);

        uint256 fee = (card.value * s_claimFee) / 10000;
        uint256 payout = card.value - fee;

        card.claimed = true; // Mark as claimed to prevent double spending
        card.receiver = payable(msg.sender);
        card.value = 0;
        s_totalFeesCollected += fee;

        // Transfer payout to receiver
        (bool sent, ) = payable(msg.sender).call{value: payout}("");
        if (!sent) revert TransferFailed();

        // Transfer fee to feeCollector
        (bool feeSent, ) = s_feeCollector.call{value: fee}("");
        if(!feeSent) revert TransferFailed();

        emit FeeCollected(s_feeCollector, fee);
        emit GiftCardClaimed(
            _cardId,
            msg.sender,
            payout,
            block.timestamp
        );
    }

    function claimGiftCardAirtime(
        uint256 _cardId,
        string memory pin,
        string memory _phoneNumber // E.g., "+2348012345678"
    ) public {
        Card storage card = giftCards[_cardId];
      
        if (card.cardId == 0) revert GiftCardNotFound(_cardId);
        if (card.claimed) revert AlreadyClaimedOrRefunded(_cardId);
        if (card.value == 0) revert AlreadyClaimedOrRefunded(_cardId); // Already refunded/claimed

        if (card.pinHash != keccak256(abi.encodePacked(pin))) revert InvalidPin(_cardId);

        // Basic phone number validation (can be more robust off-chain)
        if (bytes(_phoneNumber).length < 7) revert InvalidPhoneNumber();

        uint256 fee = (card.value * s_claimFee) / 10000;
        uint256 amountToProcess = card.value - fee; // This is the ETH amount to be converted to NGN airtime

        card.claimed = true;
        card.receiver = payable(msg.sender);
        card.value = 0;
        s_totalFeesCollected += fee;

        // Collect fee
        (bool feeSent, ) = s_feeCollector.call{value: fee}("");
        if (!feeSent) revert TransferFailed(); // Revert if fee transfer fails

        // The off-chain service will then convert USD to NGN and top up airtime
        uint256 usdEquivalent = amountToProcess.getUsdAmountFromEth(s_priceFeed);

        emit AirtimeClaimRequested(
            _cardId,
            msg.sender,
            _phoneNumber,
            usdEquivalent,
            amountToProcess, 
            block.timestamp
        );
        emit GiftCardClaimed(
            _cardId,
            msg.sender,
            amountToProcess,
            block.timestamp
        );
        emit FeeCollected(s_feeCollector, fee);
    }

    function claimGiftCardToBank(
        uint256 _cardId,
        string memory pin,
        string memory bankAccount,
        string memory bankCode
    ) external {
        Card storage card = giftCards[_cardId];

        if(card.cardId == 0) revert GiftCardNotFound(_cardId);
        if(card.claimed) revert AlreadyClaimedOrRefunded(_cardId);
        if(card.value == 0) revert AlreadyClaimedOrRefunded(_cardId);

        if(card.pinHash != keccak256(abi.encodePacked(pin))) revert InvalidPin(_cardId);

        // Calculate fee
        uint256 fee = (card.value * s_claimFee) / 10000;
        uint256 amountToProcess = card.value - fee;

        card.claimed = true;
        card.receiver = payable(msg.sender);
        card.value = 0;
        s_totalFeesCollected += fee;

        // Collect fee
        (bool feeSent, ) = s_feeCollector.call{value: fee}("");
        if (!feeSent) revert TransferFailed(); // Revert if fee transfer fails

        // The off-chain service will then convert USD to NGN and top up airtime
        uint256 usdEquivalent = amountToProcess.getUsdAmountFromEth(s_priceFeed);

        emit BankClaimRequested(
            _cardId,
            msg.sender,
            bankAccount,
            bankCode,
            usdEquivalent,
            amountToProcess, 
            block.timestamp
        );
        emit GiftCardClaimed(
            _cardId,
            msg.sender,
            amountToProcess,
            block.timestamp
        );
        emit FeeCollected(s_feeCollector, fee);
    }

    function usdValue(uint256 ethAmount) 
        public view returns (uint256)
    {
        return ethAmount.getUsdAmountFromEth(s_priceFeed);
    }

    function ethValue(uint256 usdAmount) 
        public view returns (uint256) 
    {
        return usdAmount.getEthAmountFromUsd(s_priceFeed);
    }

    function getTotalFeesCollected() external view onlyOwner returns (uint256) {
        return s_totalFeesCollected;
    }

    function setFixedFee(
        uint256 _newFee
    ) private onlyOwner {
        s_claimFee = _newFee;
    }
}