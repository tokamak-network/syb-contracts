// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {NewSybil} from "../src/NewSybil.sol";
import {INewSybil} from "../src/interfaces/INewSybil.sol";

contract NewSybilTest is Test {
    NewSybil public sybil;

    address public owner;
    address public alice;
    address public bob;
    address public charlie;

    uint256 public constant DEFAULT_STAKE = 0.01 ether;
    uint64 public constant DEFAULT_WINDOW = 240; // 4 minutes
    uint32 public constant DEFAULT_BATCH_SIZE = 100;

    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event AccountCreated(address indexed owner, uint32 indexed idx);
    event Vouched(
        address indexed attester,
        address indexed subject,
        uint256 stake
    );
    event WindowOpened(
        address indexed lo,
        address indexed hi,
        uint64 start,
        uint64 end
    );
    event Linked(
        address indexed lo,
        address indexed hi,
        uint64 windowStart,
        uint64 windowEnd
    );
    event Stolen(address indexed thief, address indexed victim, uint256 payout);
    event ClosedNoLink(address indexed caller, address indexed counterparty);

    function setUp() public {
        owner = address(this);
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        charlie = makeAddr("charlie");

        // Deploy NewSybil contract
        sybil = new NewSybil(DEFAULT_STAKE, DEFAULT_WINDOW, DEFAULT_BATCH_SIZE);

        // Fund test accounts
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(charlie, 100 ether);
    }

    // Constructor and Admin Tests

    function testConstructor() public view {
        assertEq(sybil.owner(), owner);
        assertEq(sybil.stakeS(), DEFAULT_STAKE);
        assertEq(sybil.windowT(), DEFAULT_WINDOW);
        assertEq(sybil.batchSize(), DEFAULT_BATCH_SIZE);
    }

    function testConstructorRevertsOnBadValue() public {
        vm.expectRevert(INewSybil.BadValue.selector);
        new NewSybil(0, DEFAULT_WINDOW, DEFAULT_BATCH_SIZE);

        vm.expectRevert(INewSybil.BadValue.selector);
        new NewSybil(DEFAULT_STAKE, 0, DEFAULT_BATCH_SIZE);

        vm.expectRevert(INewSybil.BadValue.selector);
        new NewSybil(DEFAULT_STAKE, DEFAULT_WINDOW, 0);
    }

    function testSetParams() public {
        uint256 newStake = 0.02 ether;
        uint64 newWindow = 300;

        sybil.setParams(newStake, newWindow);

        assertEq(sybil.stakeS(), newStake);
        assertEq(sybil.windowT(), newWindow);
    }

    function testSetParamsRevertsForNonOwner() public {
        vm.prank(alice);
        vm.expectRevert(INewSybil.NotOwner.selector);
        sybil.setParams(0.02 ether, 300);
    }

    function testSetBatchSize() public {
        uint32 newBatchSize = 200;

        sybil.setBatchSize(newBatchSize);

        assertEq(sybil.batchSize(), newBatchSize);
    }

    function testDeposit() public {
        vm.prank(alice);
        vm.expectEmit(true, false, false, true);
        emit Deposited(alice, 1 ether);
        sybil.deposit{value: 1 ether}();

        assertEq(sybil.balanceOf(alice), 1 ether);
    }

    function testDepositViaReceive() public {
        vm.prank(alice);
        vm.expectEmit(true, false, false, true);
        emit Deposited(alice, 1 ether);
        (bool success, ) = address(sybil).call{value: 1 ether}("");
        require(success, "Transfer failed");

        assertEq(sybil.balanceOf(alice), 1 ether);
    }

    function testWithdraw() public {
        vm.startPrank(alice);
        sybil.deposit{value: 2 ether}();

        uint256 balanceBefore = alice.balance;

        vm.expectEmit(true, false, false, true);
        emit Withdrawn(alice, 1 ether);
        sybil.withdraw(1 ether);

        assertEq(sybil.balanceOf(alice), 1 ether);
        assertEq(alice.balance, balanceBefore + 1 ether);
        vm.stopPrank();
    }

    function testWithdrawRevertsOnInsufficientBalance() public {
        vm.startPrank(alice);
        sybil.deposit{value: 0.5 ether}();

        vm.expectRevert(INewSybil.InsufficientBalance.selector);
        sybil.withdraw(1 ether);
        vm.stopPrank();
    }


    function testAccountCreation() public {
        assertEq(sybil.totalAccounts(), 0);

        // Vouching creates account if not exists (deposit doesn't create account)
        vm.startPrank(alice);
        vm.expectEmit(true, true, false, false);
        emit AccountCreated(alice, 1);
        vm.expectEmit(true, true, false, false);
        emit AccountCreated(bob, 2);
        sybil.vouch{value: DEFAULT_STAKE}(bob);
        vm.stopPrank();

        assertGt(sybil.accountIdx(alice), 0);
        assertGt(sybil.accountIdx(bob), 0);
        assertEq(sybil.totalAccounts(), 2);
    }

    function testVouchSingleSide() public {
        vm.startPrank(alice);
        sybil.deposit{value: DEFAULT_STAKE}();

        vm.expectEmit(true, true, false, true);
        emit Vouched(alice, bob, DEFAULT_STAKE);
        sybil.vouch(bob);

        vm.stopPrank();

        (address lo, address hi) = alice < bob ? (alice, bob) : (bob, alice);
        (
            uint64 windowStart,
            bool loFunded,
            bool hiFunded,
            uint128 stakeAmt
        ) = sybil.pairs(lo, hi);

        if (alice < bob) {
            assertTrue(loFunded);
            assertFalse(hiFunded);
        } else {
            assertFalse(loFunded);
            assertTrue(hiFunded);
        }
        assertEq(stakeAmt, DEFAULT_STAKE);
        assertEq(windowStart, 0);
    }

    function testVouchBothSidesOpensWindow() public {
        // Alice vouches for Bob
        vm.startPrank(alice);
        sybil.deposit{value: DEFAULT_STAKE}();
        sybil.vouch(bob);
        vm.stopPrank();

        // Bob vouches for Alice
        vm.startPrank(bob);
        sybil.deposit{value: DEFAULT_STAKE}();

        uint64 timestampBefore = uint64(block.timestamp);
        vm.expectEmit(true, true, false, false);
        (address lo, address hi) = alice < bob ? (alice, bob) : (bob, alice);
        emit WindowOpened(
            lo,
            hi,
            timestampBefore,
            timestampBefore + DEFAULT_WINDOW
        );

        sybil.vouch(alice);
        vm.stopPrank();

        (
            uint64 windowStart,
            bool loFunded,
            bool hiFunded,
            uint128 stakeAmt
        ) = sybil.pairs(lo, hi);
        assertTrue(loFunded);
        assertTrue(hiFunded);
        assertEq(windowStart, timestampBefore);
        assertEq(stakeAmt, DEFAULT_STAKE);
    }

    function testVouchWithPayment() public {
        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit Vouched(alice, bob, DEFAULT_STAKE);
        sybil.vouch{value: DEFAULT_STAKE}(bob);

        // Payment should be deposited
        assertEq(sybil.balanceOf(alice), 0); // Stake was deducted
    }

    function testVouchRevertsOnSelf() public {
        vm.prank(alice);
        vm.expectRevert(INewSybil.Self.selector);
        sybil.vouch{value: DEFAULT_STAKE}(alice);
    }

    function testVouchRevertsOnAlreadyVouched() public {
        vm.startPrank(alice);
        sybil.deposit{value: DEFAULT_STAKE * 2}();
        sybil.vouch(bob);

        // The error depends on whether alice is lo or hi
        if (alice < bob) {
            vm.expectRevert(INewSybil.AlreadyLo.selector);
        } else {
            vm.expectRevert(INewSybil.AlreadyHi.selector);
        }
        sybil.vouch(bob);
        vm.stopPrank();
    }

    function testVouchRevertsWhenAlreadyLinked() public {
        // Create and finalize link
        vm.startPrank(alice);
        sybil.deposit{value: DEFAULT_STAKE}();
        sybil.vouch(bob);
        vm.stopPrank();

        vm.startPrank(bob);
        sybil.deposit{value: DEFAULT_STAKE}();
        sybil.vouch(alice);
        vm.stopPrank();

        // Wait for window to pass
        vm.warp(block.timestamp + DEFAULT_WINDOW + 1);

        // Finalize
        sybil.finalize(alice, bob);

        // Try to vouch again
        vm.startPrank(alice);
        sybil.deposit{value: DEFAULT_STAKE}();
        vm.expectRevert(INewSybil.AlreadyLinked.selector);
        sybil.vouch(bob);
        vm.stopPrank();
    }

    function testCancelVouch() public {
        vm.startPrank(alice);
        sybil.deposit{value: DEFAULT_STAKE}();
        sybil.vouch(bob);

        uint256 balanceBefore = sybil.balanceOf(alice);

        vm.expectEmit(true, true, false, false);
        (address lo, address hi) = alice < bob ? (alice, bob) : (bob, alice);
        emit ClosedNoLink(alice, bob);
        sybil.cancelVouch(bob);

        assertEq(sybil.balanceOf(alice), balanceBefore + DEFAULT_STAKE);

        (, bool loFunded, bool hiFunded, uint128 stakeAmt) = sybil.pairs(
            lo,
            hi
        );
        assertFalse(loFunded);
        assertFalse(hiFunded);
        assertEq(stakeAmt, 0);
        vm.stopPrank();
    }

    function testCancelVouchRevertsIfWindowOpen() public {
        // Both vouch to open window
        vm.startPrank(alice);
        sybil.deposit{value: DEFAULT_STAKE}();
        sybil.vouch(bob);
        vm.stopPrank();

        vm.startPrank(bob);
        sybil.deposit{value: DEFAULT_STAKE}();
        sybil.vouch(alice);
        vm.stopPrank();

        // Try to cancel
        vm.prank(alice);
        vm.expectRevert(INewSybil.NoWindow.selector);
        sybil.cancelVouch(bob);
    }

    function testSteal() public {
        // Both vouch to open window
        vm.startPrank(alice);
        sybil.deposit{value: DEFAULT_STAKE}();
        sybil.vouch(bob);
        vm.stopPrank();

        vm.startPrank(bob);
        sybil.deposit{value: DEFAULT_STAKE}();
        sybil.vouch(alice);
        vm.stopPrank();

        // Alice steals during window
        uint256 balanceBefore = sybil.balanceOf(alice);

        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit Stolen(alice, bob, DEFAULT_STAKE * 2);
        sybil.steal(bob);

        assertEq(sybil.balanceOf(alice), balanceBefore + (DEFAULT_STAKE * 2));
    }

    function testStealRevertsAfterWindow() public {
        // Both vouch to open window
        vm.startPrank(alice);
        sybil.deposit{value: DEFAULT_STAKE}();
        sybil.vouch(bob);
        vm.stopPrank();

        vm.startPrank(bob);
        sybil.deposit{value: DEFAULT_STAKE}();
        sybil.vouch(alice);
        vm.stopPrank();

        // Wait for window to close
        vm.warp(block.timestamp + DEFAULT_WINDOW + 1);

        vm.prank(alice);
        vm.expectRevert(INewSybil.PastWindow.selector);
        sybil.steal(bob);
    }

    function testCloseWithoutSteal() public {
        // Both vouch to open window
        vm.startPrank(alice);
        sybil.deposit{value: DEFAULT_STAKE}();
        sybil.vouch(bob);
        vm.stopPrank();

        vm.startPrank(bob);
        sybil.deposit{value: DEFAULT_STAKE}();
        sybil.vouch(alice);
        vm.stopPrank();

        uint256 aliceBalanceBefore = sybil.balanceOf(alice);
        uint256 bobBalanceBefore = sybil.balanceOf(bob);

        // Close without stealing
        vm.prank(alice);
        vm.expectEmit(true, true, false, false);
        emit ClosedNoLink(alice, bob);
        sybil.closeWithoutSteal(bob);

        assertEq(sybil.balanceOf(alice), aliceBalanceBefore + DEFAULT_STAKE);
        assertEq(sybil.balanceOf(bob), bobBalanceBefore + DEFAULT_STAKE);
    }

    function testFinalize() public {
        // Both vouch to open window
        vm.startPrank(alice);
        sybil.deposit{value: DEFAULT_STAKE}();
        sybil.vouch(bob);
        vm.stopPrank();

        vm.startPrank(bob);
        sybil.deposit{value: DEFAULT_STAKE}();
        sybil.vouch(alice);
        vm.stopPrank();

        assertFalse(sybil.hasLink(alice, bob));

        // Wait for window to close
        vm.warp(block.timestamp + DEFAULT_WINDOW + 1);

        assertTrue(sybil.isFinalizeReady(alice, bob));

        uint256 aliceBalanceBefore = sybil.balanceOf(alice);
        uint256 bobBalanceBefore = sybil.balanceOf(bob);

        // Finalize creates the link
        (address lo, address hi) = alice < bob ? (alice, bob) : (bob, alice);
        vm.expectEmit(true, true, false, false);
        emit Linked(
            lo,
            hi,
            uint64(block.timestamp - DEFAULT_WINDOW - 1),
            uint64(block.timestamp - 1)
        );
        sybil.finalize(alice, bob);

        assertTrue(sybil.hasLink(alice, bob));
        assertTrue(sybil.isLinked(lo, hi));

        // Stakes returned
        assertEq(sybil.balanceOf(alice), aliceBalanceBefore + DEFAULT_STAKE);
        assertEq(sybil.balanceOf(bob), bobBalanceBefore + DEFAULT_STAKE);

        // Edge added to unforged queue
        assertEq(sybil.pendingEdges(), 1);
    }

    function testFinalizeRevertsIfEarly() public {
        // Both vouch to open window
        vm.startPrank(alice);
        sybil.deposit{value: DEFAULT_STAKE}();
        sybil.vouch(bob);
        vm.stopPrank();

        vm.startPrank(bob);
        sybil.deposit{value: DEFAULT_STAKE}();
        sybil.vouch(alice);
        vm.stopPrank();

        // Try to finalize immediately
        vm.expectRevert(INewSybil.Early.selector);
        sybil.finalize(alice, bob);
    }

    function testHasLink() public {
        assertFalse(sybil.hasLink(alice, bob));
        assertFalse(sybil.hasLink(alice, alice));

        // Create link
        vm.startPrank(alice);
        sybil.deposit{value: DEFAULT_STAKE}();
        sybil.vouch(bob);
        vm.stopPrank();

        vm.startPrank(bob);
        sybil.deposit{value: DEFAULT_STAKE}();
        sybil.vouch(alice);
        vm.stopPrank();

        vm.warp(block.timestamp + DEFAULT_WINDOW + 1);
        sybil.finalize(alice, bob);

        assertTrue(sybil.hasLink(alice, bob));
        assertTrue(sybil.hasLink(bob, alice)); // Order doesn't matter
    }

    function testRequiredStake() public view {
        assertEq(sybil.requiredStake(alice, bob), DEFAULT_STAKE);
    }

    function testPendingEdges() public {
        assertEq(sybil.pendingEdges(), 0);

        // Create and finalize multiple links
        address[] memory users = new address[](3);
        users[0] = alice;
        users[1] = bob;
        users[2] = charlie;

        // Alice-Bob link
        vm.startPrank(alice);
        sybil.deposit{value: DEFAULT_STAKE}();
        sybil.vouch(bob);
        vm.stopPrank();

        vm.startPrank(bob);
        sybil.deposit{value: DEFAULT_STAKE}();
        sybil.vouch(alice);
        vm.stopPrank();

        vm.warp(block.timestamp + DEFAULT_WINDOW + 1);
        sybil.finalize(alice, bob);

        assertEq(sybil.pendingEdges(), 1);
    }

    function testFuzzDeposit(uint96 amount) public {
        vm.assume(amount > 0);
        vm.deal(alice, amount);

        vm.prank(alice);
        sybil.deposit{value: amount}();

        assertEq(sybil.balanceOf(alice), amount);
    }

    function testFuzzWithdraw(
        uint96 depositAmount,
        uint96 withdrawAmount
    ) public {
        vm.assume(depositAmount > 0);
        vm.assume(withdrawAmount > 0 && withdrawAmount <= depositAmount);
        vm.deal(alice, depositAmount);

        vm.startPrank(alice);
        sybil.deposit{value: depositAmount}();
        sybil.withdraw(withdrawAmount);
        vm.stopPrank();

        assertEq(sybil.balanceOf(alice), depositAmount - withdrawAmount);
    }

    function testDepositRevertsOnZeroValue() public {
        vm.prank(alice);
        vm.expectRevert(INewSybil.BadValue.selector);
        sybil.deposit{value: 0}();
    }

    function testWithdrawRevertsOnZeroAmount() public {
        vm.startPrank(alice);
        sybil.deposit{value: 1 ether}();

        vm.expectRevert(INewSybil.BadValue.selector);
        sybil.withdraw(0);
        vm.stopPrank();
    }

    function testSetParamsRevertsOnZeroStake() public {
        vm.expectRevert(INewSybil.BadValue.selector);
        sybil.setParams(0, DEFAULT_WINDOW);
    }

    function testSetParamsRevertsOnZeroWindow() public {
        vm.expectRevert(INewSybil.BadValue.selector);
        sybil.setParams(DEFAULT_STAKE, 0);
    }

    function testSetBatchSizeRevertsOnZero() public {
        vm.expectRevert(INewSybil.BadValue.selector);
        sybil.setBatchSize(0);
    }

    function testRequiredStakeWithExistingPair() public {
        // Create a pair with custom stake
        vm.startPrank(alice);
        sybil.deposit{value: DEFAULT_STAKE}();
        sybil.vouch(bob);
        vm.stopPrank();

        // Now requiredStake should return the existing stake
        assertEq(sybil.requiredStake(alice, bob), DEFAULT_STAKE);
    }

    function testRequiredStakeForSameAddress() public view {
        // Should return default stake for same address
        assertEq(sybil.requiredStake(alice, alice), DEFAULT_STAKE);
    }

    function testIsFinalizeReadyWhenWindowNotStarted() public {
        vm.startPrank(alice);
        sybil.deposit{value: DEFAULT_STAKE}();
        sybil.vouch(bob);
        vm.stopPrank();

        // Window not started yet (only one side vouched)
        assertFalse(sybil.isFinalizeReady(alice, bob));
    }

    function testIsFinalizeReadyWhenNotBothFunded() public {
        vm.startPrank(alice);
        sybil.deposit{value: DEFAULT_STAKE}();
        sybil.vouch(bob);
        vm.stopPrank();

        assertFalse(sybil.isFinalizeReady(alice, bob));
    }

    function testIsFinalizeReadyWhenWindowStillOpen() public {
        // Both vouch to open window
        vm.startPrank(alice);
        sybil.deposit{value: DEFAULT_STAKE}();
        sybil.vouch(bob);
        vm.stopPrank();

        vm.startPrank(bob);
        sybil.deposit{value: DEFAULT_STAKE}();
        sybil.vouch(alice);
        vm.stopPrank();

        // Window still open
        assertFalse(sybil.isFinalizeReady(alice, bob));
    }

    function testCancelVouchRevertsNotLoOnly() public {
        // Both vouch
        vm.startPrank(alice);
        sybil.deposit{value: DEFAULT_STAKE}();
        sybil.vouch(bob);
        vm.stopPrank();

        vm.startPrank(bob);
        sybil.deposit{value: DEFAULT_STAKE}();
        sybil.vouch(alice);
        vm.stopPrank();

        // Wait for window to close
        vm.warp(block.timestamp + DEFAULT_WINDOW + 1);

        // Try to cancel after finalize (delete the pair first)
        sybil.finalize(alice, bob);

        // Now try to cancel should fail with StakeZero
        vm.prank(alice);
        vm.expectRevert(INewSybil.StakeZero.selector);
        sybil.cancelVouch(bob);
    }

    function testCancelVouchRevertsWhenBothFunded() public {
        // Setup: Alice vouches for Bob
        vm.startPrank(alice);
        sybil.deposit{value: DEFAULT_STAKE}();
        sybil.vouch(bob);
        vm.stopPrank();

        // Bob also vouches for Alice (now both funded)
        vm.startPrank(bob);
        sybil.deposit{value: DEFAULT_STAKE}();
        sybil.vouch(alice);
        vm.stopPrank();

        // Window is now open, cancel should fail
        vm.prank(alice);
        vm.expectRevert(INewSybil.NoWindow.selector);
        sybil.cancelVouch(bob);
    }

    function testCancelVouchNotHiOnlyError() public {
        // Have bob vouch for alice (bob is the higher address needs specific ordering)
        address user1;
        address user2;

        if (alice < bob) {
            user1 = bob;
            user2 = alice;
        } else {
            user1 = alice;
            user2 = bob;
        }

        // lo vouches first
        vm.startPrank(user2);
        sybil.deposit{value: DEFAULT_STAKE}();
        sybil.vouch(user1);
        vm.stopPrank();

        // Now hi tries to cancel (but they haven't vouched)
        // First hi needs to have balance
        vm.deal(user1, DEFAULT_STAKE);
        vm.startPrank(user1);
        sybil.deposit{value: DEFAULT_STAKE}();

        // Try to cancel without having vouched
        vm.expectRevert(INewSybil.NotHiOnly.selector);
        sybil.cancelVouch(user2);
        vm.stopPrank();
    }

    function testStealRevertsOnNoWindow() public {
        vm.startPrank(alice);
        sybil.deposit{value: DEFAULT_STAKE}();
        sybil.vouch(bob);
        vm.stopPrank();

        // Only one side vouched, no window
        vm.prank(charlie);
        vm.expectRevert(INewSybil.NoWindow.selector);
        sybil.steal(alice);
    }

    function testCloseWithoutStealRevertsOnNoWindow() public {
        vm.prank(alice);
        vm.expectRevert(INewSybil.NoWindow.selector);
        sybil.closeWithoutSteal(bob);
    }

    function testCloseWithoutStealRevertsAfterWindow() public {
        // Both vouch to open window
        vm.startPrank(alice);
        sybil.deposit{value: DEFAULT_STAKE}();
        sybil.vouch(bob);
        vm.stopPrank();

        vm.startPrank(bob);
        sybil.deposit{value: DEFAULT_STAKE}();
        sybil.vouch(alice);
        vm.stopPrank();

        // Wait for window to close
        vm.warp(block.timestamp + DEFAULT_WINDOW + 1);

        vm.prank(alice);
        vm.expectRevert(INewSybil.PastWindow.selector);
        sybil.closeWithoutSteal(bob);
    }

    function testFinalizeRevertsOnNoWindow() public {
        vm.expectRevert(INewSybil.NoWindow.selector);
        sybil.finalize(alice, bob);
    }

    function testFinalizeRevertsWhenPairDeletedAfterFinalize() public {
        // Create and finalize a link
        vm.startPrank(alice);
        sybil.deposit{value: DEFAULT_STAKE}();
        sybil.vouch(bob);
        vm.stopPrank();

        vm.startPrank(bob);
        sybil.deposit{value: DEFAULT_STAKE}();
        sybil.vouch(alice);
        vm.stopPrank();

        vm.warp(block.timestamp + DEFAULT_WINDOW + 1);
        sybil.finalize(alice, bob);

        // Try to finalize again - pair data is deleted so NoWindow error
        vm.expectRevert(INewSybil.NoWindow.selector);
        sybil.finalize(alice, bob);
    }

    function testScoreSnapshotOf() public view {
        (uint256 score, uint64 batch) = sybil.scoreSnapshotOf(alice);
        assertEq(score, 0);
        assertEq(batch, 0);
    }

    function testPendingEdgesWithNoEdges() public view {
        assertEq(sybil.pendingEdges(), 0);
    }


    function testSubmitBatch() public {
        // Create and finalize a link first
        vm.startPrank(alice);
        sybil.deposit{value: DEFAULT_STAKE}();
        sybil.vouch(bob);
        vm.stopPrank();

        vm.startPrank(bob);
        sybil.deposit{value: DEFAULT_STAKE}();
        sybil.vouch(alice);
        vm.stopPrank();

        vm.warp(block.timestamp + DEFAULT_WINDOW + 1);
        sybil.finalize(alice, bob);

        // Now we have 1 pending edge
        assertEq(sybil.pendingEdges(), 1);

        bytes32 newGraph = keccak256("newGraph");
        bytes32 newScore = keccak256("newScore");
        bytes memory proof = "";

        sybil.submitBatch(newGraph, newScore, 1, proof);

        assertEq(sybil.latestGraphRoot(), newGraph);
        assertEq(sybil.scoreRootAt(0), newScore);
        assertEq(sybil.latestBatchId(), 0);
        assertEq(sybil.batchId(), 1);
        assertEq(sybil.pendingEdges(), 0);
    }

    function testSubmitBatchRevertsOnZeroN() public {
        vm.expectRevert(INewSybil.BadValue.selector);
        sybil.submitBatch(bytes32(0), bytes32(0), 0, "");
    }

    function testSubmitBatchRevertsOnEmptyBatch() public {
        // Try to submit when there are no edges
        vm.expectRevert(INewSybil.EmptyBatch.selector);
        sybil.submitBatch(bytes32(0), bytes32(0), 1, "");
    }

    function testSubmitBatchRevertsWhenNExceedsBatchSize() public {
        // Create pending edges
        vm.startPrank(alice);
        sybil.deposit{value: DEFAULT_STAKE}();
        sybil.vouch(bob);
        vm.stopPrank();

        vm.startPrank(bob);
        sybil.deposit{value: DEFAULT_STAKE}();
        sybil.vouch(alice);
        vm.stopPrank();

        vm.warp(block.timestamp + DEFAULT_WINDOW + 1);
        sybil.finalize(alice, bob);

        // Try to submit with n > batchSize
        vm.expectRevert(INewSybil.BadValue.selector);
        sybil.submitBatch(bytes32(0), bytes32(0), DEFAULT_BATCH_SIZE + 1, "");
    }

    function testSubmitBatchRevertsWhenNExceedsAvailable() public {
        // Create 1 pending edge
        vm.startPrank(alice);
        sybil.deposit{value: DEFAULT_STAKE}();
        sybil.vouch(bob);
        vm.stopPrank();

        vm.startPrank(bob);
        sybil.deposit{value: DEFAULT_STAKE}();
        sybil.vouch(alice);
        vm.stopPrank();

        vm.warp(block.timestamp + DEFAULT_WINDOW + 1);
        sybil.finalize(alice, bob);

        // Try to submit 2 edges when only 1 is available
        vm.expectRevert(INewSybil.EmptyBatch.selector);
        sybil.submitBatch(bytes32(0), bytes32(0), 2, "");
    }

    function testSubmitMultipleBatches() public {
        // Create multiple links
        address[] memory users = new address[](4);
        users[0] = alice;
        users[1] = bob;
        users[2] = charlie;
        users[3] = makeAddr("dave");
        vm.deal(users[3], 100 ether);

        // Alice-Bob link
        vm.startPrank(alice);
        sybil.deposit{value: DEFAULT_STAKE}();
        sybil.vouch(bob);
        vm.stopPrank();

        vm.startPrank(bob);
        sybil.deposit{value: DEFAULT_STAKE}();
        sybil.vouch(alice);
        vm.stopPrank();

        vm.warp(block.timestamp + DEFAULT_WINDOW + 1);
        sybil.finalize(alice, bob);

        // Alice-Charlie link
        vm.startPrank(alice);
        sybil.deposit{value: DEFAULT_STAKE}();
        sybil.vouch(charlie);
        vm.stopPrank();

        vm.startPrank(charlie);
        sybil.deposit{value: DEFAULT_STAKE}();
        sybil.vouch(alice);
        vm.stopPrank();

        vm.warp(block.timestamp + DEFAULT_WINDOW + 1);
        sybil.finalize(alice, charlie);

        assertEq(sybil.pendingEdges(), 2);

        // Submit first batch with 1 edge
        bytes32 graph1 = keccak256("graph1");
        bytes32 score1 = keccak256("score1");
        sybil.submitBatch(graph1, score1, 1, "");

        assertEq(sybil.pendingEdges(), 1);
        assertEq(sybil.batchId(), 1);

        // Submit second batch
        bytes32 graph2 = keccak256("graph2");
        bytes32 score2 = keccak256("score2");
        sybil.submitBatch(graph2, score2, 1, "");

        assertEq(sybil.pendingEdges(), 0);
        assertEq(sybil.batchId(), 2);
    }

    function testVouchInsufficientBalanceError() public {
        vm.prank(alice);
        vm.expectRevert(INewSybil.InsufficientBalance.selector);
        sybil.vouch(bob);
    }

    function testReceiveFunctionWithValue() public {
        uint256 sendAmount = 2 ether;
        vm.deal(alice, sendAmount);

        vm.prank(alice);
        (bool success, ) = address(sybil).call{value: sendAmount}("");
        require(success, "Transfer failed");

        assertEq(sybil.balanceOf(alice), sendAmount);
    }

    function testMultipleDeposits() public {
        vm.startPrank(alice);
        sybil.deposit{value: 1 ether}();
        assertEq(sybil.balanceOf(alice), 1 ether);

        sybil.deposit{value: 2 ether}();
        assertEq(sybil.balanceOf(alice), 3 ether);

        sybil.deposit{value: 0.5 ether}();
        assertEq(sybil.balanceOf(alice), 3.5 ether);
        vm.stopPrank();
    }

    function testVouchWithExactPayment() public {
        vm.startPrank(alice);
        // Send exact amount needed
        sybil.vouch{value: DEFAULT_STAKE}(bob);

        // Balance should be 0 after stake deduction
        assertEq(sybil.balanceOf(alice), 0);
        vm.stopPrank();
    }

    function testVouchWithExcessPayment() public {
        vm.startPrank(alice);
        // Send more than needed
        uint256 excess = DEFAULT_STAKE + 1 ether;
        sybil.vouch{value: excess}(bob);

        // Excess should remain in balance
        assertEq(sybil.balanceOf(alice), 1 ether);
        vm.stopPrank();
    }

    function testStealDeletesPairData() public {
        // Both vouch to open window
        vm.startPrank(alice);
        sybil.deposit{value: DEFAULT_STAKE}();
        sybil.vouch(bob);
        vm.stopPrank();

        vm.startPrank(bob);
        sybil.deposit{value: DEFAULT_STAKE}();
        sybil.vouch(alice);
        vm.stopPrank();

        (address lo, address hi) = alice < bob ? (alice, bob) : (bob, alice);

        // Verify pair exists
        (uint64 windowStart, , , uint128 stakeAmt) = sybil.pairs(lo, hi);
        assertTrue(windowStart > 0);
        assertTrue(stakeAmt > 0);

        // Alice steals
        vm.prank(alice);
        sybil.steal(bob);

        // Verify pair is deleted
        (windowStart, , , stakeAmt) = sybil.pairs(lo, hi);
        assertEq(windowStart, 0);
        assertEq(stakeAmt, 0);
    }

    function testCloseWithoutStealDeletesPairData() public {
        // Both vouch to open window
        vm.startPrank(alice);
        sybil.deposit{value: DEFAULT_STAKE}();
        sybil.vouch(bob);
        vm.stopPrank();

        vm.startPrank(bob);
        sybil.deposit{value: DEFAULT_STAKE}();
        sybil.vouch(alice);
        vm.stopPrank();

        (address lo, address hi) = alice < bob ? (alice, bob) : (bob, alice);

        // Close without stealing
        vm.prank(alice);
        sybil.closeWithoutSteal(bob);

        // Verify pair is deleted
        (uint64 windowStart, , , uint128 stakeAmt) = sybil.pairs(lo, hi);
        assertEq(windowStart, 0);
        assertEq(stakeAmt, 0);
    }

    function testFinalizeDeletesPairData() public {
        // Both vouch to open window
        vm.startPrank(alice);
        sybil.deposit{value: DEFAULT_STAKE}();
        sybil.vouch(bob);
        vm.stopPrank();

        vm.startPrank(bob);
        sybil.deposit{value: DEFAULT_STAKE}();
        sybil.vouch(alice);
        vm.stopPrank();

        (address lo, address hi) = alice < bob ? (alice, bob) : (bob, alice);

        vm.warp(block.timestamp + DEFAULT_WINDOW + 1);
        sybil.finalize(alice, bob);

        // Verify pair is deleted
        (uint64 windowStart, , , uint128 stakeAmt) = sybil.pairs(lo, hi);
        assertEq(windowStart, 0);
        assertEq(stakeAmt, 0);

        // But link should exist
        assertTrue(sybil.isLinked(lo, hi));
    }

    function testAccountIdxIncrementsCorrectly() public {
        assertEq(sybil.nextIdx(), 1);
        assertEq(sybil.totalAccounts(), 0);

        // Create account for alice
        vm.startPrank(alice);
        sybil.vouch{value: DEFAULT_STAKE}(bob);
        vm.stopPrank();

        // Alice and Bob should have indices
        assertEq(sybil.accountIdx(alice), 1);
        assertEq(sybil.accountIdx(bob), 2);
        assertEq(sybil.nextIdx(), 3);
        assertEq(sybil.totalAccounts(), 2);

        // Create account for charlie
        vm.startPrank(charlie);
        sybil.vouch{value: DEFAULT_STAKE}(alice);
        vm.stopPrank();

        assertEq(sybil.accountIdx(charlie), 3);
        assertEq(sybil.totalAccounts(), 3);
    }

    function testHasLinkReturnsFalseForSameAddress() public view {
        assertFalse(sybil.hasLink(alice, alice));
    }

    function testHasLinkIsSymmetric() public {
        // Create link
        vm.startPrank(alice);
        sybil.deposit{value: DEFAULT_STAKE}();
        sybil.vouch(bob);
        vm.stopPrank();

        vm.startPrank(bob);
        sybil.deposit{value: DEFAULT_STAKE}();
        sybil.vouch(alice);
        vm.stopPrank();

        vm.warp(block.timestamp + DEFAULT_WINDOW + 1);
        sybil.finalize(alice, bob);

        // Check both directions
        assertTrue(sybil.hasLink(alice, bob));
        assertTrue(sybil.hasLink(bob, alice));
    }

    function testBatchSubmittedEvent() public {
        // Create and finalize a link
        vm.startPrank(alice);
        sybil.deposit{value: DEFAULT_STAKE}();
        sybil.vouch(bob);
        vm.stopPrank();

        vm.startPrank(bob);
        sybil.deposit{value: DEFAULT_STAKE}();
        sybil.vouch(alice);
        vm.stopPrank();

        vm.warp(block.timestamp + DEFAULT_WINDOW + 1);
        sybil.finalize(alice, bob);

        bytes32 newGraph = keccak256("newGraph");
        bytes32 newScore = keccak256("newScore");

        vm.expectEmit(true, false, false, false);
        emit INewSybil.BatchSubmitted(0, 1, bytes32(0), newGraph, newScore, "");
        sybil.submitBatch(newGraph, newScore, 1, "");
    }

    function testParamsUpdatedEvent() public {
        uint256 newStake = 0.02 ether;
        uint64 newWindow = 300;

        vm.expectEmit(false, false, false, true);
        emit INewSybil.ParamsUpdated(newStake, newWindow);
        sybil.setParams(newStake, newWindow);
    }

    function testBatchSizeUpdatedEvent() public {
        uint32 newBatchSize = 200;

        vm.expectEmit(false, false, false, true);
        emit INewSybil.BatchSizeUpdated(newBatchSize);
        sybil.setBatchSize(newBatchSize);
    }
}
