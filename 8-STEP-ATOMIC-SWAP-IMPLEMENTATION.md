# 8-Step Atomic Swap Implementation

This document describes the complete implementation of the 8-step atomic swap flow as specified by the user.

## Overview

The atomic swap system allows trustless token exchanges between Sepolia and Monad testnets using:
- **Maker**: Creates off-chain signatures for token approval (bravoKey wallet)
- **Resolver**: Deploys escrows and facilitates the swap (deployerKey wallet)  
- **Relayer**: Verifies escrow funding and provides secret to resolver

## Implementation Files

### Step 1 & 2: Off-Chain Signature & Secret Storage
- **`scripts/1-maker-sign-order.js`**: Creates EIP-712 signature for token approval
- **`data/swap-secrets.json`**: Stores secret, hash, signature data, and swap status

### Step 3-7: Escrow Deployment & Withdrawals
- **`examples/script/CreateOrder.s.sol`**: Updated to support all modes:
  - `MODE=deployEscrowSrc`: Resolver deploys source escrow (Step 3)
  - `MODE=deployEscrowDst`: Resolver deploys destination escrow (Step 4)
  - `MODE=withdrawDst`: Resolver withdraws destination tokens (Step 6)
  - `MODE=withdrawSrc`: Resolver withdraws source tokens (Step 7)

### Step 5: Verification
- **`scripts/5-relayer-verify.js`**: Verifies escrow funding and retrieves secret

### Step 8: Complete Demo
- **`scripts/8-step-atomic-swap.sh`**: Executes all 8 steps sequentially
- **`Makefile`**: Added `demo-8-step-atomic-swap` target

### Infrastructure Updates
- **`script/DeployResolver.s.sol`**: Auto-updates deployments.json with resolver addresses
- **`package.json`**: Added ethers and dotenv dependencies for Node.js scripts

## 8-Step Flow Implementation

### Step 1: Maker Off-Chain Signature
```bash
node scripts/1-maker-sign-order.js
```
- Maker creates EIP-712 signature approving token transfer
- Generates order hash and signature components (r, vs)
- Stores in `data/swap-secrets.json`

### Step 2: Secret Storage
- Secret and hash generated in Step 1
- All swap metadata stored in JSON format
- Status tracking for each step

### Step 3: Resolver Source Escrow Deployment
```bash
MODE=deployEscrowSrc forge script examples/script/CreateOrder.s.sol:CreateOrder \
    --rpc-url sepolia --account deployerKey --broadcast
```
- Resolver deploys source escrow on Sepolia
- Uses maker's pre-signed order from Step 1
- Transfers maker's tokens to escrow with safety deposit

### Step 4: Resolver Destination Escrow Deployment
```bash
MODE=deployEscrowDst forge script examples/script/CreateOrder.s.sol:CreateOrder \
    --rpc-url monad_testnet --account deployerKey --broadcast
```
- Resolver deploys destination escrow on Monad
- Funds escrow with destination tokens and safety deposit
- Links to source escrow via cross-chain immutables

### Step 5: Relayer Verification
```bash
node scripts/5-relayer-verify.js
```
- Verifies both escrows are properly funded
- Checks contract states and balances
- Retrieves secret for resolver to complete withdrawals

### Step 6: Resolver Destination Withdrawal
```bash
MODE=withdrawDst forge script examples/script/CreateOrder.s.sol:CreateOrder \
    --rpc-url monad_testnet --account deployerKey --broadcast
```
- Resolver calls `IBaseEscrow.withdraw(secret, immutables)` on destination escrow
- Transfers destination tokens to maker's wallet
- Secret is revealed on-chain

### Step 7: Resolver Source Withdrawal
```bash
MODE=withdrawSrc forge script examples/script/CreateOrder.s.sol:CreateOrder \
    --rpc-url sepolia --account deployerKey --broadcast
```
- Resolver calls `IBaseEscrow.withdraw(secret, immutables)` on source escrow
- Transfers source tokens from maker to resolver
- Recovers safety deposits

### Step 8: Complete Cycle Verification
- Updates swap status to completed
- Verifies final token balances
- Confirms atomic swap success

## Key Function Calls

### Source Escrow Deployment (Step 3)
```solidity
IResolverExample(resolver).deploySrc(
    immutables,        // Contains hashlock, timelocks, amounts
    signedOrder,       // Maker's EIP-712 signed order  
    r, vs,            // Signature components from Step 1
    srcAmount,        // Amount to transfer from maker
    takerTraits,      // Execution parameters
    args              // Additional arguments
);
```

### Destination Escrow Deployment (Step 4)
```solidity
IResolverExample(resolver).deployDst{value: safetyDeposit}(
    dstImmutables,              // Cross-chain escrow parameters
    srcCancellationTimestamp    // Source chain timelock reference
);
```

### Destination Withdrawal (Step 6)
```solidity
IBaseEscrow(dstEscrow).withdraw(
    secret,           // Plain text secret (reveals on-chain)
    dstImmutables     // Destination escrow parameters
);
```

### Source Withdrawal (Step 7)
```solidity
IBaseEscrow(srcEscrow).withdraw(
    secret,           // Same secret used in Step 6
    srcImmutables     // Source escrow parameters
);
```

## Configuration Management

### Single Source of Truth
- **`deployments.json`**: All contract addresses (tokens, resolvers, factories)
- **`.env`**: Wallet addresses and RPC endpoints only
- **`data/swap-secrets.json`**: Secret data and swap status
- **`examples/config/config.json`**: Protocol parameters only (amounts, timelocks)

### Auto-Updates
- Resolver deployment automatically updates `deployments.json`
- All scripts read from consistent configuration sources
- No hardcoded addresses or manual JSON updates required

## Usage

### Complete Demo Execution
```bash
make demo-8-step-atomic-swap
```

### Individual Steps
```bash
# Step 1: Create maker signature
node scripts/1-maker-sign-order.js

# Step 3: Deploy source escrow
MODE=deployEscrowSrc forge script examples/script/CreateOrder.s.sol:CreateOrder --rpc-url sepolia --account deployerKey --broadcast

# Step 4: Deploy destination escrow  
MODE=deployEscrowDst forge script examples/script/CreateOrder.s.sol:CreateOrder --rpc-url monad_testnet --account deployerKey --broadcast

# Step 5: Verify escrows
node scripts/5-relayer-verify.js

# Step 6: Destination withdrawal
MODE=withdrawDst forge script examples/script/CreateOrder.s.sol:CreateOrder --rpc-url monad_testnet --account deployerKey --broadcast

# Step 7: Source withdrawal
MODE=withdrawSrc forge script examples/script/CreateOrder.s.sol:CreateOrder --rpc-url sepolia --account deployerKey --broadcast
```

## Security Features

- **Atomic Operations**: All or nothing execution
- **Hash Time Locks**: Secret-based unlocking mechanism
- **Safety Deposits**: Incentivize proper resolver behavior
- **Timelock Mechanisms**: Withdrawal and cancellation windows
- **Off-Chain Signatures**: Secure token approval without exposing private keys
- **Cast Wallet Integration**: Encrypted wallet support for deployments

## Result

After successful execution:
- ✅ Maker has destination tokens (cross-chain swap completed)
- ✅ Resolver has source tokens (payment for facilitating swap)
- ✅ All safety deposits recovered
- ✅ Secret revealed on-chain (enabling trustless operation)
- ✅ Complete transaction history logged

This implementation provides a production-ready atomic swap system with proper error handling, configuration management, and comprehensive documentation.