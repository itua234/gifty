// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {GiftCard} from "../src/GiftCard.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployGiftCard  is Script{
    function run() external returns (GiftCard) {
        HelperConfig helperConfig = new HelperConfig();
        address ethUsdPriceFeed = helperConfig.activeNetworkConfig();

        vm.startBroadcast();

        GiftCard giftCard = new GiftCard(ethUsdPriceFeed); // Goerli ETH/USD price feed address
        console.log("GiftCard contract deployed to:", address(giftCard));

        vm.stopBroadcast();
        return giftCard;
    }
}