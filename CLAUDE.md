# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Tokamak Atomic Swap Protocol - Hackathon Demo

## Project Overview

**1inch Fusion+ Extension to Monad** - A hackathon demonstration showcasing cross-chain atomic swaps between Ethereum Sepolia and Monad testnet. The protocol uses hash-time-locked contracts (HTLCs) with the Limit Order Protocol to ensure atomic execution without trusted intermediaries.

### Hackathon Requirements Met
- ✅ **Hash-time locks**: Secret-based atomic execution
- ✅ **Time locks**: Withdrawal and cancellation windows  
- ✅ **Bidirectional**: Ethereum Sepolia ↔ Monad testnet swaps
- ✅ **On-chain execution**: Real testnet transactions
- ✅ **Limit Order Protocol**: Full 1inch integration

## Quick Start (3-minute Demo)

```bash
# Complete hackathon demo in 3 commands:
npm run hackathon:quick-deploy    # Deploy infrastructure (30s)
npm run hackathon:demo           # Execute bidirectional swaps (90s)  
npm run hackathon:verify         # Verify atomic completion (15s)
```

## Core Architecture (Corrected Implementation)

### Key Decision: ResolverExample.sol vs CreateOrder.s.sol
- ✅ **ResolverExample.sol**: Clean 138-line contract with focused functions
- ❌ **CreateOrder.s.sol**: Monolithic 600+ line script (initially used, then corrected)
- ✅ **Direct contract calls**: Production-ready interaction pattern

### Components
- **ResolverExample.sol**: Main resolver contract with `deploySrc()`, `deployDst()`, `arbitraryCalls()`
- **EscrowFactory**: Minimal proxy pattern for gas-efficient escrow deployment
- **EscrowSrc/EscrowDst**: Hash-time-locked contracts for atomic execution
- **Cross-chain coordination**: Off-chain orchestration with on-chain execution

## Development Commands

### Basic Operations
```bash
forge build                      # Compile contracts
yarn test                       # Run test suite
yarn lint                       # Solidity linting
yarn coverage                   # Coverage report
```

### Hackathon Demo Commands
```bash
# Infrastructure
npm run hackathon:quick-deploy   # Deploy factories, tokens, resolvers

# Complete Demo
npm run hackathon:demo          # Bidirectional atomic swaps

# Monitoring & Verification
npm run hackathon:balance       # Check balances once
npm run hackathon:balance-watch # Continuous monitoring
npm run hackathon:verify        # Verify swap completion

# Individual Operations
npm run hackathon:sign          # Create EIP-712 signatures
npm run resolver:deploy-src     # Deploy source escrow
npm run resolver:deploy-dst     # Deploy destination escrow
npm run resolver:withdraw-dst   # Withdraw destination (reveal secret)
npm run resolver:withdraw-src   # Withdraw source (use secret)
```

## Script Organization

### Main Demo Scripts
- **`scripts/hackathon-demo.sh`**: Complete bidirectional demo execution
- **`scripts/quick-deploy.sh`**: Infrastructure deployment (factories, tokens, resolvers)

### ResolverExample Direct Calls (Correct Architecture)
- **`scripts/resolver-deploy-src.sh`**: Direct `ResolverExample.deploySrc()` call
- **`scripts/resolver-deploy-dst.sh`**: Direct `ResolverExample.deployDst()` call
- **`scripts/resolver-withdraw.sh`**: Direct `ResolverExample.arbitraryCalls()` for withdrawals

### Helper Scripts
- **`scripts/demo-sign-order.js`**: Simplified EIP-712 order signing
- **`scripts/balance-checker.js`**: Real-time balance monitoring across chains
- **`scripts/verify-swap.js`**: Atomic swap completion verification

## Demo Flow

### Phase 1: Infrastructure (30s)
```
EscrowFactory Deployment → Test Token Deployment → Resolver Deployment → Wallet Funding
```

### Phase 2: Bidirectional Swaps (90s)
```
Sepolia → Monad: EIP-712 Signature → deploySrc() → deployDst() → arbitraryCalls()
Monad → Sepolia: EIP-712 Signature → deploySrc() → deployDst() → arbitraryCalls()
```

### Phase 3: Verification (15s)
```
Network Check → Token Verification → Atomicity Confirmation
```

## Architecture Patterns

### Atomic Swap Mechanics
1. **Secret Generation**: Cryptographic secret for hash-time locks
2. **Cross-chain Escrows**: Deterministic addresses on both chains
3. **Secret Revelation**: Destination withdrawal reveals secret on-chain
4. **Atomic Completion**: Source withdrawal uses revealed secret

### Token Transfer Flow
- **Destination Escrow**: `_uniTransfer(token, maker, amount)` + `_ethTransfer(resolver, safetyDeposit)`
- **Source Escrow**: `IERC20.safeTransfer(resolver, amount)` + `_ethTransfer(resolver, safetyDeposit)`
- **Result**: Maker gets destination tokens, Resolver gets source tokens + recovered deposits

### Time-lock Progression
```
Deploy → Withdrawal → Public Withdrawal → Cancellation → Public Cancellation
  ↓         ↓              ↓                ↓               ↓
 T=0    T+300s         T+600s           T+900s          T+1200s
```

## Environment Setup

### Required Variables (.env)
```bash
DEPLOYER_ADDRESS=0x...          # Resolver operator wallet
MAKER_ADDRESS=0x...             # Token swapper wallet
MAKER_PRIVATE_KEY_FOR_SIGNING=0x...  # For EIP-712 signatures
SEPOLIA_RPC_URL=https://rpc.sepolia.org
MONAD_RPC_URL=https://testnet-rpc.monad.xyz
```

### Cast Wallets
```bash
cast wallet import deployerKey --interactive   # For contract deployment
```

## Important Files

### Configuration
- **`deployments.json`**: Contract addresses across networks
- **`config/hackathon.json`**: Demo parameters and network settings
- **`data/swap-secrets.json`**: Generated during demo execution

### Contracts
- **`contracts/mocks/ResolverExample.sol`**: Main resolver implementation
- **`contracts/EscrowFactory.sol`**: Factory for escrow deployment
- **`contracts/EscrowSrc.sol`**: Source chain escrow
- **`contracts/EscrowDst.sol`**: Destination chain escrow

## Common Development Tasks

### Run Complete Demo
```bash
./scripts/hackathon-demo.sh
# Executes full bidirectional atomic swap demonstration
```

### Deploy Infrastructure Only
```bash
./scripts/quick-deploy.sh
# Sets up factories, tokens, and resolvers without running swaps
```

### Monitor During Demo
```bash
npm run hackathon:balance-watch
# Real-time balance monitoring during swap execution
```

### Individual Resolver Operations
```bash
CHAIN_ID=11155111 ./scripts/resolver-deploy-src.sh    # Sepolia source
CHAIN_ID=10143 ./scripts/resolver-deploy-dst.sh       # Monad destination
./scripts/resolver-withdraw.sh dst                    # Reveal secret
./scripts/resolver-withdraw.sh src                    # Use secret
```

This hackathon demo showcases a production-ready 1inch Fusion+ extension enabling secure, trustless cross-chain atomic swaps between Ethereum and Monad with preserved hash-time lock functionality.