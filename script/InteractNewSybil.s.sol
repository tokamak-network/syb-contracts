// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {NewSybil} from "../src/NewSybil.sol";

contract InteractNewSybil is Script {
    // Deployed contract address
    address constant NEWSYBIL = 0x7D6bf8923E9532625dD33F18De6bc9F628c175AC;

    function run() public {
        NewSybil sybil = NewSybil(payable(NEWSYBIL));
        
        console2.log("=== Contract State Before ===");
        console2.log("Total Accounts:", sybil.totalAccounts());
        console2.log("Stake Amount:", sybil.stakeS());
        console2.log("Window Time:", sybil.windowT());
        
        vm.startBroadcast();
        
        // 1. Deposit some ETH (this will trigger Deposited event)
        console2.log("\n=== Depositing 0.001 ETH ===");
        sybil.deposit{value: 0.001 ether}();
        console2.log("Deposit successful!");
        
        // Check balance
        console2.log("My balance in contract:", sybil.balanceOf(msg.sender));
        
        // 2. Create a second address to vouch for (we'll use a random address)
        address testSubject = 0x1234567890123456789012345678901234567890;
        
        // 3. Vouch for the test subject (this triggers AccountCreated and Vouched events)
        console2.log("\n=== Vouching for test subject ===");
        console2.log("Subject:", testSubject);
        sybil.vouch{value: 0.01 ether}(testSubject); // Send stake amount with vouch
        console2.log("Vouch successful!");
        
        vm.stopBroadcast();
        
        console2.log("\n=== Contract State After ===");
        console2.log("Total Accounts:", sybil.totalAccounts());
        console2.log("My balance:", sybil.balanceOf(msg.sender));
        console2.log("My account index:", sybil.accountIdx(msg.sender));
    }
}

