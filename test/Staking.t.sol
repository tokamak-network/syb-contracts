// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.4;

// import "forge-std/Test.sol";
// import "../src/StakingInterface.sol";

// contract MockDepositManager {
//     mapping(address => mapping(address => uint256)) private _accStaked;
//     mapping(address => uint256) private _accStakedLayer2;
//     mapping(address => uint256) private _accStakedAccount;
//     mapping(address => mapping(address => uint256)) private _pendingUnstaked;
//     mapping(address => mapping(address => uint256)) private _accUnstaked;

//     function accStaked(address layer2, address account) external view returns (uint256) {
//         return _accStaked[layer2][account];
//     }

//     function accStakedLayer2(address layer2) external view returns (uint256) {
//         return _accStakedLayer2[layer2];
//     }

//     function accStakedAccount(address account) external view returns (uint256) {
//         return _accStakedAccount[account];
//     }

//     function pendingUnstaked(address layer2, address account) external view returns (uint256) {
//         return _pendingUnstaked[layer2][account];
//     }

//     function accUnstaked(address layer2, address account) external view returns (uint256) {
//         return _accUnstaked[layer2][account];
//     }

//     // Helper functions for testing
//     function setAccStaked(address layer2, address account, uint256 amount) external {
//         _accStaked[layer2][account] = amount;
//         _accStakedLayer2[layer2] += amount;
//         _accStakedAccount[account] += amount;
//     }

//     function setPendingUnstaked(address layer2, address account, uint256 amount) external {
//         _pendingUnstaked[layer2][account] = amount;
//     }

//     function setAccUnstaked(address layer2, address account, uint256 amount) external {
//         _accUnstaked[layer2][account] = amount;
//     }
// }

// contract MockSybil {
//     mapping(address => uint32) private _scores;

//     function getScore(address user) external view returns (uint32) {
//         return _scores[user];
//     }

//     function setScore(address user, uint32 score) external {
//         _scores[user] = score;
//     }
// }

// contract StakingTest is Test {
//     Staking public stakingContract;
//     MockDepositManager public mockDepositManager;
//     MockSybil public mockSybil;
//     address public admin;
//     address public user1;
//     address public user2;
//     address public layer2Contract;

//     event DepositManagerUpdated(address indexed oldManager, address indexed newManager);
//     event SybilContractUpdated(address indexed oldSybil, address indexed newSybil);
//     event Layer2AuthorizationUpdated(address indexed layer2, bool authorized);
//     event CumulativeScoreQueried(address indexed layer2, address indexed account, uint256 stakingScore, uint32 sybilScore, uint256 cumulativeScore);

//     function setUp() public {
//         admin = address(0x123);
//         user1 = address(0x456);
//         user2 = address(0x789);
//         layer2Contract = address(0xABC);

//         // Deploy mock contracts
//         mockDepositManager = new MockDepositManager();
//         mockSybil = new MockSybil();

//         // Deploy Staking contract directly
//         stakingContract = new Staking(
//             address(mockDepositManager),
//             address(mockSybil),
//             admin
//         );

//         // Set up some test data
//         mockDepositManager.setAccStaked(layer2Contract, user1, 100 ether); // 100 WTON staked
//         mockDepositManager.setAccStaked(layer2Contract, user2, 50 ether);  // 50 WTON staked
        
//         // Set up Sybil scores
//         mockSybil.setScore(user1, 50); // 50 Sybil score
//         mockSybil.setScore(user2, 30); // 30 Sybil score
//     }

//     function testInitialization() public {
//         assertEq(stakingContract.getDepositManager(), address(mockDepositManager));
//         assertEq(stakingContract.getSybilContract(), address(mockSybil));
//         assertTrue(stakingContract.hasRole(stakingContract.ADMIN_ROLE(), admin));
//     }

//     function testGetCumulativeScore() public {
//         // User1: 100 WTON + 50 Sybil = 150 total
//         uint256 cumulativeScore = stakingContract.getCumulativeScore(layer2Contract, user1);
//         assertEq(cumulativeScore, 100 ether + 50);

//         // User2: 50 WTON + 30 Sybil = 80 total (approximately, accounting for ether unit)
//         cumulativeScore = stakingContract.getCumulativeScore(layer2Contract, user2);
//         assertEq(cumulativeScore, 50 ether + 30);
//     }

//     function testGetCumulativeScoreBreakdown() public {
//         (uint256 stakingScore, uint32 sybilScore, uint256 cumulativeScore) = 
//             stakingContract.getCumulativeScoreBreakdown(layer2Contract, user1);
        
//         assertEq(stakingScore, 100 ether);
//         assertEq(sybilScore, 50);
//         assertEq(cumulativeScore, 100 ether + 50);
//     }

//     function testBatchGetCumulativeScores() public {
//         address[] memory accounts = new address[](2);
//         accounts[0] = user1;
//         accounts[1] = user2;

//         uint256[] memory cumulativeScores = stakingContract.batchGetCumulativeScores(layer2Contract, accounts);
        
//         assertEq(cumulativeScores.length, 2);
//         assertEq(cumulativeScores[0], 100 ether + 50); // user1
//         assertEq(cumulativeScores[1], 50 ether + 30);  // user2
//     }

//     function testQueryAndEmitCumulativeScore() public {
//         vm.expectEmit(true, true, false, true);
//         emit CumulativeScoreQueried(layer2Contract, user1, 100 ether, 50, 100 ether + 50);
        
//         stakingContract.queryAndEmitCumulativeScore(layer2Contract, user1);
//     }

//     function testUpdateDepositManager() public {
//         address newDepositManager = address(0x321);
        
//         vm.expectEmit(true, true, false, false);
//         emit DepositManagerUpdated(address(mockDepositManager), newDepositManager);
        
//         vm.prank(admin);
//         stakingContract.updateDepositManager(newDepositManager);
        
//         assertEq(stakingContract.getDepositManager(), newDepositManager);
//     }

//     function testUpdateSybilContract() public {
//         address newSybilContract = address(0x654);
        
//         vm.expectEmit(true, true, false, false);
//         emit SybilContractUpdated(address(mockSybil), newSybilContract);
        
//         vm.prank(admin);
//         stakingContract.updateSybilContract(newSybilContract);
        
//         assertEq(stakingContract.getSybilContract(), newSybilContract);
//     }

//     function testSetLayer2Authorization() public {
//         vm.expectEmit(true, false, false, true);
//         emit Layer2AuthorizationUpdated(layer2Contract, true);
        
//         vm.prank(admin);
//         stakingContract.setLayer2Authorization(layer2Contract, true);
        
//         assertTrue(stakingContract.isLayer2Authorized(layer2Contract));
//     }

//     function testOnlyAdminFunctions() public {
//         address newDepositManager = address(0x321);
        
//         vm.expectRevert();
//         vm.prank(user1); // Not admin
//         stakingContract.updateDepositManager(newDepositManager);
        
//         vm.expectRevert();
//         vm.prank(user1); // Not admin
//         stakingContract.updateSybilContract(newDepositManager);
        
//         vm.expectRevert();
//         vm.prank(user1); // Not admin
//         stakingContract.setLayer2Authorization(layer2Contract, true);
//     }

//     function testRevertZeroAddresses() public {
//         // Test zero layer2 address
//         vm.expectRevert("Staking: Layer2 cannot be zero address");
//         stakingContract.getCumulativeScore(address(0), user1);

//         // Test zero account address
//         vm.expectRevert("Staking: Account cannot be zero address");
//         stakingContract.getCumulativeScore(layer2Contract, address(0));
//     }

//     function testRevertEmptyBatchArray() public {
//         address[] memory emptyArray = new address[](0);
        
//         vm.expectRevert("Staking: Accounts array cannot be empty");
//         stakingContract.batchGetCumulativeScores(layer2Contract, emptyArray);
//     }

//     function testZeroScoreScenarios() public {
//         address userWithNoStake = address(0x999);
        
//         // User with no stake and no sybil score should return 0
//         uint256 cumulativeScore = stakingContract.getCumulativeScore(layer2Contract, userWithNoStake);
//         assertEq(cumulativeScore, 0);
        
//         // User with stake but no sybil score
//         mockDepositManager.setAccStaked(layer2Contract, userWithNoStake, 75 ether);
//         cumulativeScore = stakingContract.getCumulativeScore(layer2Contract, userWithNoStake);
//         assertEq(cumulativeScore, 75 ether); // Only staking score
//     }

//     function testScoreCalculationLogic() public {
//         // Test the core requirement: 1 WTON = 1 score point
//         // User has 100 WTON staked + 50 Sybil score = 150 total
        
//         uint256 expectedStakingScore = 100 ether; // 100 WTON
//         uint32 expectedSybilScore = 50;
//         uint256 expectedCumulative = expectedStakingScore + uint256(expectedSybilScore);
        
//         (uint256 stakingScore, uint32 sybilScore, uint256 cumulativeScore) = 
//             stakingContract.getCumulativeScoreBreakdown(layer2Contract, user1);
        
//         assertEq(stakingScore, expectedStakingScore, "Staking score should equal WTON amount");
//         assertEq(sybilScore, expectedSybilScore, "Sybil score should match set value");
//         assertEq(cumulativeScore, expectedCumulative, "Cumulative should be sum of both scores");
        
//         // Verify the direct function also returns the same
//         uint256 directCumulative = stakingContract.getCumulativeScore(layer2Contract, user1);
//         assertEq(directCumulative, expectedCumulative, "Direct cumulative call should match breakdown");
//     }
// } 