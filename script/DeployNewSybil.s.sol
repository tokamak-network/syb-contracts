// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {NewSybil} from "../src/NewSybil.sol";

contract DeployNewSybil is Script {
    function run() public returns (address newSybilAddress) {
        // Get deployment parameters from environment variables with sensible defaults
        uint256 stakeAmount = vm.envOr("STAKE_AMOUNT", uint256(0.01 ether));
        uint64 windowTime = uint64(vm.envOr("WINDOW_TIME", uint256(240))); // 4 minutes default
        uint32 batchSize = uint32(vm.envOr("BATCH_SIZE", uint256(100))); // 100 edges per batch

        console2.log("Deploying NewSybil with parameters:");
        console2.log("Stake Amount:", stakeAmount);
        console2.log("Window Time:", windowTime, "seconds");
        console2.log("Batch Size:", batchSize, "edges");

        vm.startBroadcast();

        NewSybil newSybil = new NewSybil(stakeAmount, windowTime, batchSize);
        newSybilAddress = address(newSybil);

        vm.stopBroadcast();

        console2.log("NewSybil deployed at:", newSybilAddress);
        console2.log("Owner:", newSybil.owner());

        return newSybilAddress;
    }
}
