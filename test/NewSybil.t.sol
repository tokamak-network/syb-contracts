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

    // ========== Constructor & Admin Tests ==========

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
}
