import { BigInt, Bytes, Address } from "@graphprotocol/graph-ts";
import {
  ParamsUpdated,
  BatchSizeUpdated,
  Deposited,
  Withdrawn,
  AccountCreated,
  Vouched,
  WindowOpened as WindowOpenedEvent,
  Stolen as StolenEvent,
  ClosedNoLink as ClosedNoLinkEvent,
  Linked as LinkedEvent,
  BatchSubmitted,
  ScoreSynced,
} from "../generated/NewSybil/NewSybil";
import {
  ContractConfig,
  Account,
  Deposit,
  Withdrawal,
  Vouch,
  Pair,
  WindowOpened,
  Link,
  Steal,
  CloseNoLink,
  Batch,
  ScoreSnapshot,
  ParamsUpdate,
  BatchSizeUpdate,
  GlobalStats,
} from "../generated/schema";

// Helper to get or create ContractConfig
function getOrCreateConfig(): ContractConfig {
  let config = ContractConfig.load("config");
  if (config == null) {
    config = new ContractConfig("config");
    config.owner = Bytes.empty();
    config.stakeAmount = BigInt.fromI32(0);
    config.windowTime = BigInt.fromI32(0);
    config.batchSize = 0;
    config.totalAccounts = 0;
    config.latestBatchId = BigInt.fromI32(0);
    config.latestGraphRoot = null;
    config.nextEdgeId = 1;
    config.lastForgedId = 0;
  }
  return config;
}

// Helper to get or create GlobalStats
function getOrCreateStats(): GlobalStats {
  let stats = GlobalStats.load("stats");
  if (stats == null) {
    stats = new GlobalStats("stats");
    stats.totalDeposits = BigInt.fromI32(0);
    stats.totalWithdrawals = BigInt.fromI32(0);
    stats.totalVouches = 0;
    stats.totalLinks = 0;
    stats.totalSteals = 0;
    stats.totalBatches = 0;
    stats.totalAccounts = 0;
  }
  return stats;
}

// Helper to get or create Account
function getOrCreateAccount(address: Address, timestamp: BigInt, txHash: Bytes): Account {
  let id = address.toHexString();
  let account = Account.load(id);
  if (account == null) {
    account = new Account(id);
    account.address = address;
    account.index = 0; // Will be set by AccountCreated event
    account.balance = BigInt.fromI32(0);
    account.createdAt = timestamp;
    account.createdTx = txHash;
  }
  return account;
}

// Helper to get pair ID (always lo + hi order)
function getPairId(lo: Address, hi: Address): string {
  return lo.toHexString() + "-" + hi.toHexString();
}

// Helper to order addresses
function orderAddresses(a: Address, b: Address): Address[] {
  if (a.toHexString() < b.toHexString()) {
    return [a, b];
  }
  return [b, a];
}

// Event Handlers

export function handleParamsUpdated(event: ParamsUpdated): void {
  let config = getOrCreateConfig();
  config.stakeAmount = event.params.stakeS;
  config.windowTime = event.params.windowT;
  config.save();

  // Create historical record
  let id = event.transaction.hash.toHexString() + "-" + event.logIndex.toString();
  let update = new ParamsUpdate(id);
  update.stakeAmount = event.params.stakeS;
  update.windowTime = event.params.windowT;
  update.timestamp = event.block.timestamp;
  update.blockNumber = event.block.number;
  update.transactionHash = event.transaction.hash;
  update.save();
}

export function handleBatchSizeUpdated(event: BatchSizeUpdated): void {
  let config = getOrCreateConfig();
  config.batchSize = event.params.batchSize.toI32();
  config.save();

  // Create historical record
  let id = event.transaction.hash.toHexString() + "-" + event.logIndex.toString();
  let update = new BatchSizeUpdate(id);
  update.batchSize = event.params.batchSize.toI32();
  update.timestamp = event.block.timestamp;
  update.blockNumber = event.block.number;
  update.transactionHash = event.transaction.hash;
  update.save();
}

export function handleDeposited(event: Deposited): void {
  let account = getOrCreateAccount(event.params.user, event.block.timestamp, event.transaction.hash);
  account.balance = account.balance.plus(event.params.amount);
  account.save();

  // Create deposit record
  let id = event.transaction.hash.toHexString() + "-" + event.logIndex.toString();
  let deposit = new Deposit(id);
  deposit.user = account.id;
  deposit.amount = event.params.amount;
  deposit.timestamp = event.block.timestamp;
  deposit.blockNumber = event.block.number;
  deposit.transactionHash = event.transaction.hash;
  deposit.save();

  // Update stats
  let stats = getOrCreateStats();
  stats.totalDeposits = stats.totalDeposits.plus(event.params.amount);
  stats.save();
}

export function handleWithdrawn(event: Withdrawn): void {
  let account = getOrCreateAccount(event.params.user, event.block.timestamp, event.transaction.hash);
  account.balance = account.balance.minus(event.params.amount);
  account.save();

  // Create withdrawal record
  let id = event.transaction.hash.toHexString() + "-" + event.logIndex.toString();
  let withdrawal = new Withdrawal(id);
  withdrawal.user = account.id;
  withdrawal.amount = event.params.amount;
  withdrawal.timestamp = event.block.timestamp;
  withdrawal.blockNumber = event.block.number;
  withdrawal.transactionHash = event.transaction.hash;
  withdrawal.save();

  // Update stats
  let stats = getOrCreateStats();
  stats.totalWithdrawals = stats.totalWithdrawals.plus(event.params.amount);
  stats.save();
}

export function handleAccountCreated(event: AccountCreated): void {
  let account = getOrCreateAccount(event.params.owner, event.block.timestamp, event.transaction.hash);
  account.index = event.params.idx.toI32();
  account.save();

  // Update config
  let config = getOrCreateConfig();
  config.totalAccounts = config.totalAccounts + 1;
  config.save();

  // Update stats
  let stats = getOrCreateStats();
  stats.totalAccounts = stats.totalAccounts + 1;
  stats.save();
}

export function handleVouched(event: Vouched): void {
  let attester = getOrCreateAccount(event.params.attester, event.block.timestamp, event.transaction.hash);
  let subject = getOrCreateAccount(event.params.subject, event.block.timestamp, event.transaction.hash);
  attester.save();
  subject.save();

  // Create vouch record
  let id = event.transaction.hash.toHexString() + "-" + event.logIndex.toString();
  let vouch = new Vouch(id);
  vouch.attester = attester.id;
  vouch.subject = subject.id;
  vouch.stake = event.params.stake;
  vouch.timestamp = event.block.timestamp;
  vouch.blockNumber = event.block.number;
  vouch.transactionHash = event.transaction.hash;
  vouch.save();

  // Update or create pair
  let ordered = orderAddresses(event.params.attester, event.params.subject);
  let lo = ordered[0];
  let hi = ordered[1];
  let pairId = getPairId(lo, hi);
  let pair = Pair.load(pairId);
  
  if (pair == null) {
    pair = new Pair(pairId);
    pair.lo = lo.toHexString();
    pair.hi = hi.toHexString();
    pair.loFunded = false;
    pair.hiFunded = false;
    pair.stakeAmount = event.params.stake;
    pair.windowStart = null;
    pair.windowEnd = null;
    pair.status = "PENDING";
    pair.createdAt = event.block.timestamp;
  }

  // Determine who vouched
  if (event.params.attester.toHexString() == lo.toHexString()) {
    pair.loFunded = true;
  } else {
    pair.hiFunded = true;
  }
  pair.updatedAt = event.block.timestamp;
  pair.save();

  // Update stats
  let stats = getOrCreateStats();
  stats.totalVouches = stats.totalVouches + 1;
  stats.save();
}

export function handleWindowOpened(event: WindowOpenedEvent): void {
  let lo = getOrCreateAccount(event.params.lo, event.block.timestamp, event.transaction.hash);
  let hi = getOrCreateAccount(event.params.hi, event.block.timestamp, event.transaction.hash);
  lo.save();
  hi.save();

  // Create window opened record
  let id = event.transaction.hash.toHexString() + "-" + event.logIndex.toString();
  let window = new WindowOpened(id);
  window.lo = lo.id;
  window.hi = hi.id;
  window.start = event.params.start;
  window.end = event.params.end;
  window.timestamp = event.block.timestamp;
  window.blockNumber = event.block.number;
  window.transactionHash = event.transaction.hash;
  window.save();

  // Update pair
  let pairId = getPairId(event.params.lo, event.params.hi);
  let pair = Pair.load(pairId);
  if (pair != null) {
    pair.windowStart = event.params.start;
    pair.windowEnd = event.params.end;
    pair.status = "WINDOW_OPEN";
    pair.updatedAt = event.block.timestamp;
    pair.save();
  }
}

export function handleStolen(event: StolenEvent): void {
  let thief = getOrCreateAccount(event.params.thief, event.block.timestamp, event.transaction.hash);
  let victim = getOrCreateAccount(event.params.victim, event.block.timestamp, event.transaction.hash);
  
  // Update thief balance
  thief.balance = thief.balance.plus(event.params.payout);
  thief.save();
  victim.save();

  // Create steal record
  let id = event.transaction.hash.toHexString() + "-" + event.logIndex.toString();
  let steal = new Steal(id);
  steal.thief = thief.id;
  steal.victim = victim.id;
  steal.payout = event.params.payout;
  steal.timestamp = event.block.timestamp;
  steal.blockNumber = event.block.number;
  steal.transactionHash = event.transaction.hash;
  steal.save();

  // Update pair status
  let ordered = orderAddresses(event.params.thief, event.params.victim);
  let pairId = getPairId(ordered[0], ordered[1]);
  let pair = Pair.load(pairId);
  if (pair != null) {
    pair.status = "STOLEN";
    pair.updatedAt = event.block.timestamp;
    pair.save();
  }

  // Update stats
  let stats = getOrCreateStats();
  stats.totalSteals = stats.totalSteals + 1;
  stats.save();
}

export function handleClosedNoLink(event: ClosedNoLinkEvent): void {
  let caller = getOrCreateAccount(event.params.caller, event.block.timestamp, event.transaction.hash);
  let counterparty = getOrCreateAccount(event.params.counterparty, event.block.timestamp, event.transaction.hash);
  caller.save();
  counterparty.save();

  // Create close record
  let id = event.transaction.hash.toHexString() + "-" + event.logIndex.toString();
  let close = new CloseNoLink(id);
  close.caller = caller.id;
  close.counterparty = counterparty.id;
  close.timestamp = event.block.timestamp;
  close.blockNumber = event.block.number;
  close.transactionHash = event.transaction.hash;
  close.save();

  // Update pair status
  let ordered = orderAddresses(event.params.caller, event.params.counterparty);
  let pairId = getPairId(ordered[0], ordered[1]);
  let pair = Pair.load(pairId);
  if (pair != null) {
    pair.status = "CANCELLED";
    pair.updatedAt = event.block.timestamp;
    pair.save();
  }
}

export function handleLinked(event: LinkedEvent): void {
  let lo = getOrCreateAccount(event.params.lo, event.block.timestamp, event.transaction.hash);
  let hi = getOrCreateAccount(event.params.hi, event.block.timestamp, event.transaction.hash);
  lo.save();
  hi.save();

  // Create link record
  let linkId = getPairId(event.params.lo, event.params.hi);
  let link = new Link(linkId);
  link.lo = lo.id;
  link.hi = hi.id;
  link.loIndex = lo.index;
  link.hiIndex = hi.index;
  link.windowStart = event.params.windowStart;
  link.windowEnd = event.params.windowEnd;
  link.createdAt = event.block.timestamp;
  link.blockNumber = event.block.number;
  link.transactionHash = event.transaction.hash;
  link.edgeId = 0;  // Will be updated
  link.forgedInBatch = null;
  link.save();

  // Update pair status
  let pair = Pair.load(linkId);
  if (pair != null) {
    pair.status = "LINKED";
    pair.updatedAt = event.block.timestamp;
    pair.save();
  }

  // Update config (track edge ID)
  let config = getOrCreateConfig();
  link.edgeId = config.nextEdgeId;
  config.nextEdgeId = config.nextEdgeId + 1;
  config.save();
  link.save();

  // Update stats
  let stats = getOrCreateStats();
  stats.totalLinks = stats.totalLinks + 1;
  stats.save();
}

export function handleBatchSubmitted(event: BatchSubmitted): void {
  let batchIdStr = event.params.batchId.toString();
  let batch = new Batch(batchIdStr);
  batch.batchId = event.params.batchId;
  batch.edgeCount = event.params.count.toI32();
  batch.storageHash = event.params.storageHash;
  batch.graphRoot = event.params.newGraphRoot;
  batch.scoreRoot = event.params.newScoreRoot;
  batch.edgesPacked = event.params.edgesPacked;
  batch.timestamp = event.block.timestamp;
  batch.blockNumber = event.block.number;
  batch.transactionHash = event.transaction.hash;
  batch.save();

  // Update config
  let config = getOrCreateConfig();
  config.latestBatchId = event.params.batchId;
  config.latestGraphRoot = event.params.newGraphRoot;
  config.lastForgedId = config.lastForgedId + event.params.count.toI32();
  config.save();

  // Update stats
  let stats = getOrCreateStats();
  stats.totalBatches = stats.totalBatches + 1;
  stats.save();
}

export function handleScoreSynced(event: ScoreSynced): void {
  let account = getOrCreateAccount(event.params.user, event.block.timestamp, event.transaction.hash);
  account.save();

  // Create score snapshot
  let id = event.params.user.toHexString() + "-" + event.params.batchId.toString();
  let snapshot = new ScoreSnapshot(id);
  snapshot.user = account.id;
  snapshot.batchId = event.params.batchId;
  snapshot.score = event.params.score;
  snapshot.timestamp = event.block.timestamp;
  snapshot.blockNumber = event.block.number;
  snapshot.transactionHash = event.transaction.hash;
  snapshot.save();
}
