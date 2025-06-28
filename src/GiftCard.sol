// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;


/**
 * @title GiftCard
 * @dev A smart contract for creating and claiming decentralized gift cards.
 * Users can create gift cards with an associated Ether value and a PIN code.
 * The receiver can claim the Ether by providing the correct PIN.
*/
contract GiftCard {
    error GiftCardNotFound(uint256 cardId);
    error NotAuthorized(address caller);
    error AlreadyClaimed(uint256 cardId);
    error InvalidPin(uint256 cardId);
    error IncorrectValue(uint256 expected, uint256 received);
    error CardLocked(uint256 unlockTimestamp);
    error InvalidReceiver(address receiver);
    error ZeroValueNotAllowed();

    struct Card {
        uint256 cardId;
        address payable creator;
        address payable receiver; 
        uint256 value;
        bytes32 pinHash;
        bool claimed;
        uint256 createdAt;
    }

    mapping(uint256 => Card) public giftCards;
    uint256 private nextCardId;

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

    constructor() {
        nextCardId = 1;
    }

    function createGiftCard() public payable {
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
            createdAt: block.timestamp
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
            uint256 createdAt
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
            card.createdAt
        );
    }
}