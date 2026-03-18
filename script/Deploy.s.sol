// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {EpixTipping} from "../src/EpixTipping.sol";

contract Deploy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        EpixTipping tipping = new EpixTipping();

        console.log("EpixTipping deployed at:", address(tipping));

        vm.stopBroadcast();
    }
}
