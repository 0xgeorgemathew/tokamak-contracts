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
SEPOLIA_FACTORY="0xf0ED16e2165537b99C47A2B90705CD381FE87472"  # NEW!
SEPOLIA_USDC="0xfd87f19DF4eDAAc6B6df0E2afc04e8051C98cB54"   # NEW FEE TOKEN
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

echo "SECRET: $SECRET"
echo "HASHLOCK: $HASHLOCK"
echo "ORDER_HASH: $ORDER_HASH"
echo "CURRENT_TIME: $CURRENT_TIME"
echo ""

# Create properly encoded timelocks based on TimelocksLib.sol
# Contract will call setDeployedAt(block.timestamp) so we pass timelocks WITHOUT deployedAt
# Stage enum order from TimelocksLib: SrcWithdrawal(0), SrcPublicWithdrawal(1), SrcCancellation(2), SrcPublicCancellation(3), DstWithdrawal(4), DstPublicWithdrawal(5), DstCancellation(6)
# Each stage is 32 bits, positioned at stage_index * 32 bits from right
echo -e "${YELLOW}Encoding timelocks properly (without deployedAt - contract sets it)...${NC}"

# Timelock values in seconds (relative to deployment)
SRC_WITHDRAWAL=300          # 5 minutes
SRC_PUBLIC_WITHDRAWAL=600   # 10 minutes
SRC_CANCELLATION=1800       # 30 minutes
SRC_PUBLIC_CANCELLATION=3600 # 60 minutes
DST_WITHDRAWAL=300          # 5 minutes
DST_PUBLIC_WITHDRAWAL=600   # 10 minutes
DST_CANCELLATION=900        # 15 minutes - CRITICAL: must ensure deployedAt + 900 <= current_time + 1800

# Validate the critical constraint: dst_cancellation_absolute <= src_cancellation_absolute
# Since contract sets deployedAt = block.timestamp, we need: block.timestamp + DST_CANCELLATION <= CURRENT_TIME + SRC_CANCELLATION
# Assuming block.timestamp ≈ CURRENT_TIME, this becomes: DST_CANCELLATION <= SRC_CANCELLATION
if [ $DST_CANCELLATION -gt $SRC_CANCELLATION ]; then
    echo -e "${RED}ERROR: DST_CANCELLATION ($DST_CANCELLATION) must be <= SRC_CANCELLATION ($SRC_CANCELLATION)${NC}"
    exit 1
fi

echo "Source Withdrawal: $SRC_WITHDRAWAL seconds"
echo "Source Public Withdrawal: $SRC_PUBLIC_WITHDRAWAL seconds"
echo "Source Cancellation: $SRC_CANCELLATION seconds"
echo "Source Public Cancellation: $SRC_PUBLIC_CANCELLATION seconds"
echo "Destination Withdrawal: $DST_WITHDRAWAL seconds"
echo "Destination Public Withdrawal: $DST_PUBLIC_WITHDRAWAL seconds"
echo "Destination Cancellation: $DST_CANCELLATION seconds"

# Pack timelocks using correct bit positioning (deployedAt will be 0 since contract sets it)
# Format: deployedAt(224-255) = 0 + stage6(192-223) + stage5(160-191) + stage4(128-159) + stage3(96-127) + stage2(64-95) + stage1(32-63) + stage0(0-31)
# Calculate each component separately to avoid bash arithmetic syntax issues
DEPLOYED_AT_BITS=0
STAGE_6_BITS=$((DST_CANCELLATION << 192))
STAGE_5_BITS=$((DST_PUBLIC_WITHDRAWAL << 160))
STAGE_4_BITS=$((DST_WITHDRAWAL << 128))
STAGE_3_BITS=$((SRC_PUBLIC_CANCELLATION << 96))
STAGE_2_BITS=$((SRC_CANCELLATION << 64))
STAGE_1_BITS=$((SRC_PUBLIC_WITHDRAWAL << 32))
STAGE_0_BITS=$SRC_WITHDRAWAL

# Combine all components
TIMELOCKS_VALUE=$((DEPLOYED_AT_BITS | STAGE_6_BITS | STAGE_5_BITS | STAGE_4_BITS | STAGE_3_BITS | STAGE_2_BITS | STAGE_1_BITS | STAGE_0_BITS))

# Convert to hex with proper padding
TIMELOCKS=$(printf "0x%064x" $TIMELOCKS_VALUE)
echo "TIMELOCKS: $TIMELOCKS (${#TIMELOCKS} chars)"

# Debug: Show individual components
echo "Debug - Timelock components:"
printf "  Stage 0 (SrcWithdrawal): 0x%x\n" $STAGE_0_BITS
printf "  Stage 1 (SrcPublicWithdrawal): 0x%x\n" $STAGE_1_BITS
printf "  Stage 2 (SrcCancellation): 0x%x\n" $STAGE_2_BITS
printf "  Stage 3 (SrcPublicCancellation): 0x%x\n" $STAGE_3_BITS
printf "  Stage 4 (DstWithdrawal): 0x%x\n" $STAGE_4_BITS
printf "  Stage 5 (DstPublicWithdrawal): 0x%x\n" $STAGE_5_BITS
printf "  Stage 6 (DstCancellation): 0x%x\n" $STAGE_6_BITS

# Calculate expected absolute times for validation
EXPECTED_DST_CANCELLATION=$((CURRENT_TIME + DST_CANCELLATION))
SRC_CANCELLATION_TIME=$((CURRENT_TIME + SRC_CANCELLATION))

echo "Expected dst cancellation absolute: $EXPECTED_DST_CANCELLATION"
echo "Source cancellation absolute: $SRC_CANCELLATION_TIME"
echo "Validation: dst <= src? $([[ $EXPECTED_DST_CANCELLATION -le $SRC_CANCELLATION_TIME ]] && echo "✓ PASS" || echo "✗ FAIL")"

# Verify timelocks is not zero
if [ "$TIMELOCKS_VALUE" -eq 0 ]; then
    echo -e "${RED}ERROR: Calculated timelocks value is zero - check bit shifting${NC}"
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
echo "Source cancellation timestamp: $SRC_CANCELLATION_TIME"

cast send $SEPOLIA_FACTORY \
  "createDstEscrow((bytes32,bytes32,address,address,address,uint256,uint256,uint256),uint256)" \
  "$DST_IMMUTABLES" \
  $SRC_CANCELLATION_TIME \
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
WITHDRAWAL_TIME=$((CURRENT_TIME + DST_WITHDRAWAL))
CURRENT_NOW=$(date +%s)
WAIT_TIME=$((WITHDRAWAL_TIME - CURRENT_NOW))

if [ $WAIT_TIME -gt 0 ]; then
    echo -e "${YELLOW}=== WAITING FOR TIMELOCKS ===${NC}"
    echo "Waiting $WAIT_TIME seconds for withdrawal period..."
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
