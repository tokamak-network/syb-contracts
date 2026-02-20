// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {INewSybil} from "./interfaces/INewSybil.sol";

contract NewSybil is INewSybil {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status = _NOT_ENTERED;

    modifier nonReentrant() {
        if (_status != _NOT_ENTERED) revert();
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }

    address public owner;
    uint256 public stakeS; // default stake (wei) for NEW pairs
    uint64 public windowT; // steal window (seconds)
    uint32 public batchSize; // max edges per submit

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(uint256 _s, uint64 _t, uint32 _batchSize) {
        if (_s == 0 || _t == 0 || _batchSize == 0) revert BadValue();
        owner = msg.sender;
        stakeS = _s;
        windowT = _t;
        batchSize = _batchSize;
        emit ParamsUpdated(_s, _t);
        emit BatchSizeUpdated(_batchSize);
    }

    function setParams(uint256 _s, uint64 _t) external onlyOwner {
        if (_s == 0 || _t == 0) revert BadValue();
        stakeS = _s;
        windowT = _t;
        emit ParamsUpdated(_s, _t);
    }

    function setBatchSize(uint32 _n) external onlyOwner {
        if (_n == 0) revert BadValue();
        batchSize = _n;
        emit BatchSizeUpdated(_n);
    }

    mapping(address => uint32) public accountIdx; // 1-based; 0 = unset
    mapping(address => uint256) public balanceOf; // available ETH balance
    uint32 public nextIdx = 1;

    function totalAccounts() external view returns (uint32) {
        return nextIdx - 1;
    }

    function _ensureIdx(address a) internal returns (uint32 idx) {
        idx = accountIdx[a];
        if (idx != 0) return idx;
        require(nextIdx != type(uint32).max, "IDX_EXHAUSTED");
        idx = nextIdx++;
        accountIdx[a] = idx;
        emit AccountCreated(a, idx);
    }

    function deposit() external payable {
        if (msg.value == 0) revert BadValue();
        _increaseBalance(msg.sender, msg.value);
    }

    function withdraw(uint256 amount) external nonReentrant {
        if (amount == 0) revert BadValue();
        uint256 bal = balanceOf[msg.sender];
        if (bal < amount) revert InsufficientBalance();
        balanceOf[msg.sender] = bal - amount;
        (bool ok, ) = msg.sender.call{value: amount}("");
        if (!ok) revert EthXferFail();
        emit Withdrawn(msg.sender, amount);
    }

    receive() external payable {
        _increaseBalance(msg.sender, msg.value);
    }

    function _increaseBalance(address user, uint256 amount) internal {
        if (amount == 0) {
            return;
        }
        balanceOf[user] += amount;
        emit Deposited(user, amount);
    }

    function _deductStake(address user, uint256 amount) internal {
        uint256 bal = balanceOf[user];
        if (bal < amount) revert InsufficientBalance();
        balanceOf[user] = bal - amount;
    }

    function _addrOrder(
        address a,
        address b
    ) internal pure returns (address lo, address hi, bool callerIsLo) {
        if (a == b) revert Self();
        if (a < b) {
            return (a, b, true);
        }
        return (b, a, false);
    }

    mapping(address => mapping(address => PairPacked)) public pairs; // [lo][hi]
    mapping(address => mapping(address => bool)) public isLinked; // [lo][hi]

    bytes32 public latestGraphRoot; // overwritten each batch
    mapping(uint64 => bytes32) public scoreRootAt; // batchId => scoreRoot
    uint64 public latestBatchId;

    mapping(uint32 => uint72) public unforged;
    uint32 public nextEdgeId = 1; // next id to write
    uint32 public lastForgedId = 0; // last processed id
    uint64 public batchId = 0; // increments each submit

    mapping(address => ScoreSnap) public scoreSnapshot;

    function hasLink(address a, address b) public view returns (bool) {
        if (a == b) return false;
        (address lo, address hi, ) = _addrOrder(a, b);
        return isLinked[lo][hi];
    }

    function requiredStake(
        address x,
        address y
    ) external view returns (uint256) {
        if (x == y) return stakeS;
        (address lo, address hi, ) = _addrOrder(x, y);
        PairPacked storage p = pairs[lo][hi];
        return p.stakeAmt == 0 ? stakeS : uint256(p.stakeAmt);
    }

    function isFinalizeReady(address x, address y) public view returns (bool) {
        (address lo, address hi, ) = _addrOrder(x, y);
        PairPacked storage p = pairs[lo][hi];
        if (p.windowStart == 0) return false;
        if (!(p.loFunded && p.hiFunded)) return false;
        return block.timestamp > (p.windowStart + windowT);
    }

    function vouch(address subject) external payable nonReentrant {
        _ensureIdx(msg.sender);
        _ensureIdx(subject);

        (address lo, address hi, bool callerIsLo) = _addrOrder(
            msg.sender,
            subject
        );
        if (isLinked[lo][hi]) revert AlreadyLinked();

        PairPacked storage p = pairs[lo][hi];

        uint256 req = p.stakeAmt == 0 ? stakeS : uint256(p.stakeAmt);
        if (msg.value > 0) {
            _increaseBalance(msg.sender, msg.value);
        }
        if (p.stakeAmt == 0) {
            if (req == 0) revert StakeZero();
            if (req > type(uint128).max) revert BadValue();
            p.stakeAmt = uint128(req);
        }

        if (callerIsLo) {
            if (p.loFunded) revert AlreadyLo();
            _deductStake(msg.sender, req);
            p.loFunded = true;
        } else {
            if (p.hiFunded) revert AlreadyHi();
            _deductStake(msg.sender, req);
            p.hiFunded = true;
        }

        emit Vouched(msg.sender, subject, req);

        if (p.windowStart == 0 && p.loFunded && p.hiFunded) {
            uint64 start = uint64(block.timestamp);
            p.windowStart = start;
            emit WindowOpened(lo, hi, start, start + windowT);
        }
    }

    function cancelVouch(address counterparty) external nonReentrant {
        (address lo, address hi, bool callerIsLo) = _addrOrder(
            msg.sender,
            counterparty
        );
        PairPacked storage p = pairs[lo][hi];

        if (p.windowStart != 0) revert NoWindow();
        uint256 s = uint256(p.stakeAmt);
        if (s == 0) revert StakeZero();

        if (callerIsLo) {
            if (!(p.loFunded && !p.hiFunded)) revert NotLoOnly();
            p.loFunded = false;
        } else {
            if (!(p.hiFunded && !p.loFunded)) revert NotHiOnly();
            p.hiFunded = false;
        }

        balanceOf[msg.sender] += s;

        if (!p.loFunded && !p.hiFunded) {
            p.stakeAmt = 0;
        }

        emit ClosedNoLink(msg.sender, counterparty);
    }

    function steal(address counterparty) external nonReentrant {
        (address lo, address hi, ) = _addrOrder(msg.sender, counterparty);
        PairPacked storage p = pairs[lo][hi];

        if (p.windowStart == 0) revert NoWindow();
        if (block.timestamp > p.windowStart + windowT) revert PastWindow();
        if (!(p.loFunded && p.hiFunded)) revert NotBothFunded();

        uint256 s = uint256(p.stakeAmt);
        if (s == 0) revert StakeZero();

        delete pairs[lo][hi];
        balanceOf[msg.sender] += s * 2;

        emit Stolen(msg.sender, counterparty, s * 2);
    }

    function closeWithoutSteal(address counterparty) external nonReentrant {
        (address lo, address hi, ) = _addrOrder(msg.sender, counterparty);
        PairPacked storage p = pairs[lo][hi];

        if (p.windowStart == 0) revert NoWindow();
        if (block.timestamp > p.windowStart + windowT) revert PastWindow();
        if (!(p.loFunded && p.hiFunded)) revert NotBothFunded();

        uint256 s = uint256(p.stakeAmt);
        if (s == 0) revert StakeZero();

        delete pairs[lo][hi];
        balanceOf[lo] += s;
        balanceOf[hi] += s;

        emit ClosedNoLink(msg.sender, counterparty);
    }

    function finalize(address a, address b) external nonReentrant {
        (address lo, address hi, ) = _addrOrder(a, b);
        PairPacked storage p = pairs[lo][hi];

        if (p.windowStart == 0) revert NoWindow();
        if (block.timestamp <= p.windowStart + windowT) revert Early();
        if (!(p.loFunded && p.hiFunded)) revert NotBothFunded();
        if (isLinked[lo][hi]) revert AlreadyLinked();

        uint256 s = uint256(p.stakeAmt);
        if (s == 0) revert StakeZero();

        isLinked[lo][hi] = true;

        uint64 ws = p.windowStart;
        uint64 we = ws + windowT;

        delete pairs[lo][hi];
        balanceOf[lo] += s;
        balanceOf[hi] += s;

        emit Linked(lo, hi, ws, we);

        uint32 ilo = accountIdx[lo];
        uint32 ihi = accountIdx[hi];
        if (ilo == 0 || ihi == 0) revert MissingIdx();

        uint32 id = nextEdgeId++;
        unforged[id] = (uint72(ilo) << 32) | uint72(ihi);
    }

    function cancelLink(address counterparty) external nonReentrant {
        (address lo, address hi, ) = _addrOrder(msg.sender, counterparty);

        if (!isLinked[lo][hi]) revert NotLinked();

        isLinked[lo][hi] = false;

        emit LinkCancelled(lo, hi, msg.sender);

        uint32 ilo = accountIdx[lo];
        uint32 ihi = accountIdx[hi];
        if (ilo == 0 || ihi == 0) revert MissingIdx();

        uint32 id = nextEdgeId++;
        unforged[id] = (uint72(1) << 64) | (uint72(ilo) << 32) | uint72(ihi);
    }

    function submitBatch(
        bytes32 newGraph,
        bytes32 newScore,
        uint32 n,
        bytes calldata proof
    ) external nonReentrant {
        if (n == 0) revert BadValue();

        uint32 start = lastForgedId + 1;
        uint32 endSnapshot = nextEdgeId - 1;
        if (endSnapshot < start) revert EmptyBatch();

        uint32 avail = endSnapshot - lastForgedId;
        if (n > batchSize) revert BadValue();
        if (n > avail) revert EmptyBatch();

        (
            bytes memory edgesPacked,
            bytes32 storageHash
        ) = _buildEdgesAndStorageHash(start, n);

        bytes32 pubInputs = sha256(
            abi.encodePacked(
                latestGraphRoot,
                scoreRootAt[latestBatchId],
                newGraph,
                newScore,
                batchId,
                batchSize,
                n,
                storageHash
            )
        );

        if (!_verifyProof(proof, pubInputs)) {
            revert VerifyFail();
        }

        latestGraphRoot = newGraph;
        scoreRootAt[batchId] = newScore;
        latestBatchId = batchId;

        _emitBatchSubmitted(n, storageHash, newGraph, newScore, edgesPacked);

        _deleteForgedEdges(start, n);

        lastForgedId = lastForgedId + n;
        unchecked {
            batchId += 1;
        }
    }

    function _buildEdgesAndStorageHash(
        uint32 start,
        uint32 n
    ) internal view returns (bytes memory edgesPacked, bytes32 storageHash) {
        edgesPacked = new bytes(uint256(n) * 9);
        uint256 off = 0;

        for (uint32 i = 0; i < n; ++i) {
            uint72 w = unforged[start + i];
            uint32 ilo = uint32(w >> 32);
            uint32 ihi = uint32(w);
            uint8 flag = uint8(w >> 64);

            edgesPacked[off + 0] = bytes1(uint8(ilo >> 24));
            edgesPacked[off + 1] = bytes1(uint8(ilo >> 16));
            edgesPacked[off + 2] = bytes1(uint8(ilo >> 8));
            edgesPacked[off + 3] = bytes1(uint8(ilo));
            edgesPacked[off + 4] = bytes1(uint8(ihi >> 24));
            edgesPacked[off + 5] = bytes1(uint8(ihi >> 16));
            edgesPacked[off + 6] = bytes1(uint8(ihi >> 8));
            edgesPacked[off + 7] = bytes1(uint8(ihi));
            edgesPacked[off + 8] = bytes1(flag);
            off += 9;
        }

        storageHash = sha256(
            abi.encodePacked(batchId, start, n, edgesPacked)
        );
    }
    function _emitBatchSubmitted(
        uint32 n,
        bytes32 storageHash,
        bytes32 newGraph,
        bytes32 newScore,
        bytes memory edgesPacked
    ) internal {
        emit BatchSubmitted(
            batchId,
            n,
            storageHash,
            newGraph,
            newScore,
            edgesPacked
        );
    }

    function _deleteForgedEdges(uint32 start, uint32 n) internal {
        for (uint32 i = 0; i < n; ++i) {
            delete unforged[start + i];
        }
    }

    function _verifyProof(
        bytes calldata,
        bytes32
    ) internal pure returns (bool) {
        return true;
    }

    function pendingEdges() external view returns (uint32) {
        uint32 endSnapshot = nextEdgeId - 1;
        if (endSnapshot < lastForgedId) return 0;
        return endSnapshot - lastForgedId;
    }

    function scoreSnapshotOf(
        address user
    ) external view returns (uint256 score, uint64 batch) {
        ScoreSnap memory s = scoreSnapshot[user];
        return (s.score, s.batchId);
    }
}
