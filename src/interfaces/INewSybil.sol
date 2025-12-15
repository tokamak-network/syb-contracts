// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface INewSybil {
    // Errors
    error AlreadyHi();
    error AlreadyLo();
    error AlreadyLinked();
    error BadValue();
    error Early();
    error EmptyBatch();
    error NoWindow();
    error NotBothFunded();
    error NotHiOnly();
    error NotLoOnly();
    error NotOwner();
    error PastWindow();
    error Self();
    error StakeZero();
    error VerifyFail();
    error EthXferFail();
    error MissingIdx();
    error InsufficientBalance();
    error NotParticipant();
    error NotLinked();

    // Events
    event ParamsUpdated(uint256 stakeS, uint64 windowT);
    event BatchSizeUpdated(uint32 batchSize);
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
    event Stolen(address indexed thief, address indexed victim, uint256 payout);
    event ClosedNoLink(address indexed caller, address indexed counterparty);
    event Linked(
        address indexed lo,
        address indexed hi,
        uint64 windowStart,
        uint64 windowEnd
    );
    event BatchSubmitted(
        uint64 indexed batchId,
        uint32 count,
        bytes32 storageHash,
        bytes32 newGraphRoot,
        bytes32 newScoreRoot,
        bytes edgesPacked
    );
    event ScoreSynced(
        address indexed user,
        uint64 indexed batchId,
        uint256 score
    );
     event LinkCancelled(address indexed lo, address indexed hi, address indexed caller);
    
    // Structs
    struct PairPacked {
        uint64 windowStart;
        bool loFunded;
        bool hiFunded;
        uint128 stakeAmt;
    }

    struct ScoreSnap {
        uint256 score;
        uint64 batchId;
    }

    // Admin Functions
    function setParams(uint256 _s, uint64 _t) external;

    function setBatchSize(uint32 _n) external;

    // Account Management
    function totalAccounts() external view returns (uint32);

    function deposit() external payable;

    function withdraw(uint256 amount) external;

    // Vouching Functions
    function vouch(address subject) external payable;

    function cancelVouch(address counterparty) external;

    function steal(address counterparty) external;

    function closeWithoutSteal(address counterparty) external;

    function finalize(address a, address b) external;

    function cancelLink(address counterparty) external;

    // Batch Submission
    function submitBatch(
        bytes32 newGraph,
        bytes32 newScore,
        uint32 n,
        bytes calldata proof
    ) external;

    // View Functions
    function owner() external view returns (address);

    function stakeS() external view returns (uint256);

    function windowT() external view returns (uint64);

    function batchSize() external view returns (uint32);

    function accountIdx(address user) external view returns (uint32);

    function balanceOf(address user) external view returns (uint256);

    function nextIdx() external view returns (uint32);

    function pairs(
        address lo,
        address hi
    )
        external
        view
        returns (
            uint64 windowStart,
            bool loFunded,
            bool hiFunded,
            uint128 stakeAmt
        );

    function isLinked(address lo, address hi) external view returns (bool);

    function latestGraphRoot() external view returns (bytes32);

    function scoreRootAt(uint64 batchId) external view returns (bytes32);

    function latestBatchId() external view returns (uint64);

    function unforged(uint32 edgeId) external view returns (uint72);

    function nextEdgeId() external view returns (uint32);

    function lastForgedId() external view returns (uint32);

    function batchId() external view returns (uint64);

    function scoreSnapshot(
        address user
    ) external view returns (uint256 score, uint64 batchId);

    function hasLink(address a, address b) external view returns (bool);

    function requiredStake(
        address x,
        address y
    ) external view returns (uint256);

    function isFinalizeReady(address x, address y) external view returns (bool);

    function pendingEdges() external view returns (uint32);

    function scoreSnapshotOf(
        address user
    ) external view returns (uint256 score, uint64 batch);
}
