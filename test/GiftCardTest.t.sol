// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {GiftCard} from "../src/GiftCard.sol";
import { DeployGiftCard } from "../script/DeployGiftCard.s.sol";
import { MockV3Aggregator } from "./mocks/MockV3Aggregator.sol";
import { PriceConverter } from "../src/PriceConverter.sol";

contract GiftCardTest is Test {
    GiftCard public giftCard;
    MockV3Aggregator public mockFeed;

    address user = makeAddr("alice");

    function setUp() public {
        DeployGiftCard deployGiftCard = new DeployGiftCard();
        giftCard = deployGiftCard.run();
        mockFeed = new MockV3Aggregator(8, 2000 * 1e8); // 8 decimals, $2000 price
    }

    function testCanCreateGiftCard() public {
        vm.deal(user, 1 ether);
        vm.prank(user);

        giftCard.createGiftCard{value: 1 ether}(block.timestamp + 1 days, "1234");

        (
            uint256 cardId,
            address creator,
            ,
            uint256 value,
            bool claimed,
            ,
        ) = giftCard.getGiftCardDetails(1);

        assertEq(cardId, 1);
        assertEq(creator, user);
        assertEq(value, 1 ether);
        assertEq(claimed, false);
    }

    function testGetUsdAmountFromEth() public view {
        uint256 usdAmount = PriceConverter.getUsdAmountFromEth(1 ether, mockFeed);
        assertEq(usdAmount, 2000 * 1e18); // 1 ETH = $2000
    }

    function testGetEthAmountFromUsd() public view {
        uint256 ethAmount = PriceConverter.getEthAmountFromUsd(2000 * 1e18, mockFeed);
        assertEq(ethAmount, 1 ether);
    }

    function testReclaimAfterExpiry() public {
        vm.deal(user, 1 ether);
        vm.startPrank(user);
            giftCard.createGiftCard{value: 1 ether}(block.timestamp + 1, "1234");

            skip(2); // simulate time passing
            giftCard.reclaimExpiredCard(1, "1234");

            (, , , uint256 value, bool claimed, , ) = giftCard.getGiftCardDetails(1);
        vm.stopPrank();

        assertEq(value, 0);
        assertEq(claimed, true);
    }
}