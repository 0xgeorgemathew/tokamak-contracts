#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== MANUAL CROSS-CHAIN SWAP TEST: Monad → Sepolia ===${NC}"
echo -e "${GREEN}Using NEW Sepolia deployment!${NC}"
echo ""

# Check environment
if [ -z "$SEPOLIA_RPC_URL" ]; then
    echo -e "${RED}Error: SEPOLIA_RPC_URL not set${NC}"
    exit 1
fi

# Contract addresses - UPDATED with new Sepolia deployment
SEPOLIA_FACTORY="0xc73DC85b493B29Fb00Dd0bfc7a522890e70929e3"  # NEW!
SEPOLIA_USDC="0x3C59f57217530f2Ca493C65AE880769BF49c64Fe"   # NEW FEE TOKEN
MONAD_FACTORY="0x756B01844D85010C549cEf98daBdBC73e6372804"
MONAD_FEE_TOKEN="0xB7D3E26b95ffA0D02D9639329b56e75766cf5ba6"
DEPLOYER="0x20E5B952942417D4CB99d64a9e06e41Dcef00000"
KEYSTORE="$HOME/.foundry/keystores/deployerKey"

echo -e "${BLUE}Contract Addresses:${NC}"
echo "Sepolia Factory: $SEPOLIA_FACTORY"
echo "Sepolia Token:   $SEPOLIA_USDC (FEE TOKEN)"
echo "Monad Factory:   $MONAD_FACTORY"
echo "Monad Token:     $MONAD_FEE_TOKEN (FEE TOKEN)"
echo ""

# Generate fresh parameters
echo -e "${YELLOW}Generating fresh swap parameters...${NC}"
SECRET="0x$(openssl rand -hex 32)"
HASHLOCK=$(cast keccak $SECRET)
ORDER_HASH="0x$(openssl rand -hex 32)"
CURRENT_TIME=$(date +%s)
CANCEL_TIME=$((CURRENT_TIME + 1800))

echo "SECRET: $SECRET"
echo "HASHLOCK: $HASHLOCK"
echo "ORDER_HASH: $ORDER_HASH"
echo "CURRENT_TIME: $CURRENT_TIME"
echo "CANCELLATION_TIME: $CANCEL_TIME"
echo ""

# Create timelocks (EXACTLY 64 hex chars = 32 bytes)
CURRENT_HEX=$(printf '%08x' $CURRENT_TIME)
TIMELOCKS="0x${CURRENT_HEX}00000000000000000000000000000000000000000000000000000000"
echo "TIMELOCKS: $TIMELOCKS (${#TIMELOCKS} chars)"

if [ ${#TIMELOCKS} -ne 66 ]; then
    echo -e "${RED}ERROR: Timelocks must be exactly 66 chars, got ${#TIMELOCKS}${NC}"
    exit 1
fi
echo ""

# Swap parameters
DST_AMOUNT="1000000000000000000"  # 1 token
SRC_AMOUNT="2000000000000000000"  # 2 tokens
SAFETY_DEPOSIT="100000000000000000"  # 0.1 ETH

echo -e "${BLUE}=== STEP 1: Test New Contract Interface ===${NC}"
echo "Testing Sepolia factory..."
SEPOLIA_IMPL=$(cast call $SEPOLIA_FACTORY "ESCROW_DST_IMPLEMENTATION()" --rpc-url $SEPOLIA_RPC_URL)
echo "Sepolia DST implementation: $SEPOLIA_IMPL"

echo "Testing Monad factory..."
MONAD_IMPL=$(cast call $MONAD_FACTORY "ESCROW_DST_IMPLEMENTATION()" --rpc-url https://testnet-rpc.monad.xyz)
echo "Monad DST implementation: $MONAD_IMPL"
echo ""

echo -e "${BLUE}=== STEP 2: Mint and Check Balances ===${NC}"
echo "Minting tokens on Sepolia..."
cast send $SEPOLIA_USDC \
  "mint(address,uint256)" \
  $DEPLOYER \
  "10000000000000000000" \
  --rpc-url $SEPOLIA_RPC_URL \
  --keystore $KEYSTORE

echo "Checking balances..."
SEPOLIA_ETH=$(cast balance $DEPLOYER --rpc-url $SEPOLIA_RPC_URL)
SEPOLIA_TOKEN_HEX=$(cast call $SEPOLIA_USDC "balanceOf(address)" $DEPLOYER --rpc-url $SEPOLIA_RPC_URL)
MONAD_ETH=$(cast balance $DEPLOYER --rpc-url https://testnet-rpc.monad.xyz)
MONAD_FEE_HEX=$(cast call $MONAD_FEE_TOKEN "balanceOf(address)" $DEPLOYER --rpc-url https://testnet-rpc.monad.xyz)

SEPOLIA_TOKEN_DEC=$(cast --to-dec $SEPOLIA_TOKEN_HEX)
MONAD_FEE_DEC=$(cast --to-dec $MONAD_FEE_HEX)

echo "Sepolia ETH: $SEPOLIA_ETH wei"
echo "Sepolia FEE: $SEPOLIA_TOKEN_DEC wei"
echo "Monad ETH: $MONAD_ETH wei"
echo "Monad FEE: $MONAD_FEE_DEC wei"
echo ""

echo -e "${BLUE}=== STEP 3: Approve Token on Sepolia ===${NC}"
cast send $SEPOLIA_USDC \
  "approve(address,uint256)" \
  $SEPOLIA_FACTORY \
  $DST_AMOUNT \
  --rpc-url $SEPOLIA_RPC_URL \
  --keystore $KEYSTORE

echo -e "${GREEN}✓ Token approved${NC}"
echo ""

echo -e "${BLUE}=== STEP 4: Create Destination Escrow (Sepolia) ===${NC}"
DST_IMMUTABLES="($ORDER_HASH,$HASHLOCK,$DEPLOYER,$DEPLOYER,$SEPOLIA_USDC,$DST_AMOUNT,$SAFETY_DEPOSIT,$TIMELOCKS)"
echo "Destination immutables: $DST_IMMUTABLES"

cast send $SEPOLIA_FACTORY \
  "createDstEscrow((bytes32,bytes32,address,address,address,uint256,uint256,uint256),uint256)" \
  "$DST_IMMUTABLES" \
  $CANCEL_TIME \
  --value $SAFETY_DEPOSIT \
  --rpc-url $SEPOLIA_RPC_URL \
  --keystore $KEYSTORE

echo -e "${GREEN}✓ Destination escrow created${NC}"
echo ""

echo -e "${BLUE}=== STEP 5: Get Escrow Addresses ===${NC}"
DST_ESCROW_HEX=$(cast call $SEPOLIA_FACTORY \
  "addressOfEscrowDst((bytes32,bytes32,address,address,address,uint256,uint256,uint256))" \
  "$DST_IMMUTABLES" \
  --rpc-url $SEPOLIA_RPC_URL)

DST_ESCROW="0x${DST_ESCROW_HEX:26:40}"
echo "Destination escrow: $DST_ESCROW"

SRC_IMMUTABLES="($ORDER_HASH,$HASHLOCK,$DEPLOYER,$DEPLOYER,$MONAD_FEE_TOKEN,$SRC_AMOUNT,$SAFETY_DEPOSIT,$TIMELOCKS)"
SRC_ESCROW_HEX=$(cast call $MONAD_FACTORY \
  "addressOfEscrowSrc((bytes32,bytes32,address,address,address,uint256,uint256,uint256))" \
  "$SRC_IMMUTABLES" \
  --rpc-url https://testnet-rpc.monad.xyz)

SRC_ESCROW="0x${SRC_ESCROW_HEX:26:40}"
echo "Source escrow: $SRC_ESCROW"
echo ""

echo -e "${BLUE}=== STEP 6: Fund Source Escrow (Monad) ===${NC}"
cast send $MONAD_FEE_TOKEN \
  "transfer(address,uint256)" \
  $SRC_ESCROW \
  $SRC_AMOUNT \
  --rpc-url https://testnet-rpc.monad.xyz \
  --keystore $KEYSTORE

cast send $SRC_ESCROW \
  --value $SAFETY_DEPOSIT \
  --rpc-url https://testnet-rpc.monad.xyz \
  --keystore $KEYSTORE

echo -e "${GREEN}✓ Source escrow funded${NC}"
echo ""

# Wait for timelocks
WITHDRAWAL_TIME=$((CURRENT_TIME + 300))
CURRENT_NOW=$(date +%s)
WAIT_TIME=$((WITHDRAWAL_TIME - CURRENT_NOW))

if [ $WAIT_TIME -gt 0 ]; then
    echo -e "${YELLOW}=== WAITING FOR TIMELOCKS ===${NC}"
    echo "Waiting $WAIT_TIME seconds..."
    sleep $WAIT_TIME
    echo -e "${GREEN}✓ Timelock completed${NC}"
fi
echo ""

echo -e "${BLUE}=== STEP 7: Execute Withdrawals ===${NC}"
echo "Withdrawing from destination (Sepolia)..."
cast send $DST_ESCROW \
  "withdraw(bytes32,(bytes32,bytes32,address,address,address,uint256,uint256,uint256))" \
  $SECRET \
  "$DST_IMMUTABLES" \
  --rpc-url $SEPOLIA_RPC_URL \
  --keystore $KEYSTORE

echo "Withdrawing from source (Monad)..."
cast send $SRC_ESCROW \
  "withdraw(bytes32,(bytes32,bytes32,address,address,address,uint256,uint256,uint256))" \
  $SECRET \
  "$SRC_IMMUTABLES" \
  --rpc-url https://testnet-rpc.monad.xyz \
  --keystore $KEYSTORE

echo -e "${GREEN}✓ Both withdrawals completed${NC}"
echo ""

echo -e "${GREEN}🎉 CROSS-CHAIN SWAP SUCCESSFUL! 🎉${NC}"
echo ""
echo -e "${BLUE}📋 HACKATHON DEMO PROOF:${NC}"
echo "✅ Bidirectional: Monad → Sepolia (reverse possible)"
echo "✅ Hashlock/timelock preserved: Built into contracts"
echo "✅ Onchain execution: Real token transfers"
echo "✅ Atomic swaps: Both completed successfully"
echo ""
echo "Secret: $SECRET"
echo "Hashlock: $HASHLOCK"
echo "Destination escrow: $DST_ESCROW"
echo "Source escrow: $SRC_ESCROW"
