# NewSybil Subgraph

This subgraph indexes the NewSybil contract on Sepolia testnet.

## Contract Details

- **Address**: `0x7D6bf8923E9532625dD33F18De6bc9F628c175AC`
- **Network**: Sepolia (Chain ID: 11155111)
- **Start Block**: 9794615

## Setup

```bash
cd subgraph
npm install
```

## Build

```bash
# Generate types from schema and ABI
npm run codegen

# Build the subgraph
npm run build
```

## Deploy

### Option 1: Goldsky (Recommended - Free Tier)

1. Install Goldsky CLI:
```bash
npm install -g @goldsky/cli
```

2. Login to Goldsky:
```bash
goldsky login
```

3. Deploy:
```bash
npm run deploy:goldsky
```

### Option 2: The Graph Studio

1. Create a subgraph on [The Graph Studio](https://thegraph.com/studio/)

2. Authenticate:
```bash
graph auth --studio <YOUR_DEPLOY_KEY>
```

3. Deploy:
```bash
npm run deploy:studio
```

### Option 3: Local Graph Node (Development)

1. Start a local Graph Node (requires Docker)

2. Create and deploy:
```bash
npm run create:local
npm run deploy:local
```

## Indexed Events

| Event | Description |
|-------|-------------|
| `ParamsUpdated` | Contract parameters changed |
| `BatchSizeUpdated` | Batch size configuration changed |
| `Deposited` | User deposited ETH |
| `Withdrawn` | User withdrew ETH |
| `AccountCreated` | New account registered |
| `Vouched` | User vouched for another |
| `WindowOpened` | Steal window started |
| `Stolen` | Stake was stolen |
| `ClosedNoLink` | Pair closed without link |
| `Linked` | Two accounts are now linked |
| `BatchSubmitted` | ZK batch processed |
| `ScoreSynced` | User score updated |

## Example Queries

### Get all accounts
```graphql
{
  accounts(first: 100) {
    id
    address
    index
    balance
  }
}
```

### Get all links
```graphql
{
  links(first: 100) {
    id
    lo {
      address
    }
    hi {
      address
    }
    windowStart
    windowEnd
  }
}
```

### Get recent deposits
```graphql
{
  deposits(first: 10, orderBy: timestamp, orderDirection: desc) {
    user {
      address
    }
    amount
    timestamp
  }
}
```

### Get global stats
```graphql
{
  globalStats(id: "stats") {
    totalAccounts
    totalLinks
    totalDeposits
    totalWithdrawals
  }
}
```

### Get user's links
```graphql
{
  account(id: "0x...") {
    linksAsLo {
      hi {
        address
      }
    }
    linksAsHi {
      lo {
        address
      }
    }
  }
}
```

