// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
library PriceConverter {
    function getPrice(AggregatorV3Interface priceFeed) internal view returns (uint256) {
        (
            /* uint80 roundID */,
            int price,
            /*uint startedAt*/,
            /*uint timeStamp*/,
            /*uint80 answeredInRound*/
        ) = priceFeed.latestRoundData();
        //Price of ETH in terms of USD
        // Chainlink returns price with 8 decimals, so scale it up to 18 decimals
        return uint256(price * 1e10);
    }

    function getUsdAmountFromEth(
        uint256 ethAmount,
        AggregatorV3Interface priceFeed
    ) internal view returns (uint256) {
        uint256 ethPrice = getPrice(priceFeed);
        uint256 ethAmountInUsd = (ethPrice * ethAmount) / 1e18;
        return ethAmountInUsd;
    }

    function getEthAmountFromUsd(
        uint256 usdAmount,
        AggregatorV3Interface priceFeed
    ) internal view returns (uint256) {
        uint256 ethPrice = getPrice(priceFeed); // e.g., 3000 * 1e8
        return (usdAmount * 1e18) / ethPrice;   // Convert USD to ETH (ETH has 18 decimals)
    }
}
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

    constructor(address priceFeed) {
        nextCardId = 1;
        s_priceFeed = AggregatorV3Interface(priceFeed);
    }

    modifier onlyCardCreator(uint256 _cardId) {
        if (giftCards[_cardId].creator != msg.sender) {
            revert NotAuthorized(msg.sender);
        }
        _;
    }

    function createGiftCard(uint256 _expireAt) public payable {
        if(msg.value == 0) revert ZeroValueNotAllowed();
        if(msg.sender == address(0)) revert NotAuthorized(msg.sender);

        uint256 cardId = nextCardId;
        bytes32 pinHash = keccak256(abi.encodePacked(block.timestamp, msg.sender, cardId));

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
        // Ensure the card exists before returning details.
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

    function reclaimExpiredCard(uint256 _cardId) 
        external 
        onlyCardCreator(_cardId) 
    {
        Card storage card = giftCards[_cardId];

        if (card.claimed) {
            revert AlreadyClaimedOrRefunded(_cardId);
        }
        if (block.timestamp < card.expireAt) {
            revert CardNotExpired(card.expireAt);
        }
        if (card.value == 0) {
            revert AlreadyClaimedOrRefunded(_cardId);
        }

        uint256 amount = card.value;
        card.value = 0;
        card.claimed = true; // Mark as claimed to prevent double spending

        (
            bool callSuccess,
            //bytes memory dataReturned
        ) = payable(msg.sender).call{value: amount}("");
        if(!callSuccess) revert TransferFailed();

        emit GiftCardClaimed(
            _cardId,
            msg.sender,
            amount,
            block.timestamp
        );
    }
}