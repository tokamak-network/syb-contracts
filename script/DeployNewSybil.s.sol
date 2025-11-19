// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.0;

// import {Script, console2} from "forge-std/Script.sol";
// import {NewSybil} from "../src/NewSybil.sol";

// contract DeployNewSybil is Script {
//     function run() public returns (address newSybil) {
//         // Get deployment parameters from environment variables
//         uint256 stakeAmount = vm.envOr("STAKE_AMOUNT", uint256(0.01 ether)); 
//         uint64 windowTime = uint64(vm.envOr("WINDOW_TIME", uint256(240))); 
//         uint32 batchSize = uint32(vm.envOr("BATCH_SIZE", uint256(5))); 

//         console2.log("Deploying NewSybil with parameters:");
//         console2.log("Stake Amount:", stakeAmount);
//         console2.log("Window Time:", windowTime);
//         console2.log("Batch Size:", batchSize);

//         vm.startBroadcast();
        
//         newSybil = address(new NewSybil(stakeAmount, windowTime, batchSize));
        
//         vm.stopBroadcast();

//         console2.log("NewSybil deployed at:", newSybil);
        
//         return newSybil;
//     }
// }
