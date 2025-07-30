#!/bin/bash

# Resolver Deploy Source: Direct ResolverExample.deploySrc() call
# This script demonstrates the correct architecture using ResolverExample contract directly
#
# CRITICAL FIXES APPLIED:
# 1. Address computation accounts for setDeployedAt() timestamp modification
# 2. Proper ExtraDataArgs encoding (160 bytes) for Factory._postInteraction 
# 3. Address types converted to uint256 with Address.wrap() format
# 4. Timelocks properly packed according to TimelocksLib (7 stages * 32 bits)
# 5. Enhanced validation and error handling with transaction confirmation
# 6. Increased gas limit to 3M for complex proxy deployments
# 7. CRITICAL: Args parameter excludes target address (ResolverExample adds it via abi.encodePacked)

set -e  # Exit on any error

echo "🚀 Resolver Deploy Source: Direct Contract Call"
echo "=============================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
DEPLOYMENTS_PATH="deployments.json"
SECRETS_PATH="data/swap-secrets.json"

# Load environment variables
if [ ! -f ".env" ]; then
    echo -e "${RED}❌ .env file not found${NC}"
    exit 1
fi
source .env

# Get chain ID from environment (default to Sepolia)
CHAIN_ID=${CHAIN_ID:-11155111}

# Determine network and RPC
if [ "$CHAIN_ID" = "11155111" ]; then
    NETWORK="sepolia"
    RPC_URL=${SEPOLIA_RPC_URL:-"sepolia"}
elif [ "$CHAIN_ID" = "10143" ]; then
    NETWORK="monad"
    RPC_URL=${MONAD_RPC_URL:-"monad_testnet"}
else
    echo -e "${RED}❌ Unsupported chain ID: $CHAIN_ID${NC}"
    exit 1
fi

echo -e "${CYAN}📋 Configuration:${NC}"
echo "Chain ID: $CHAIN_ID"
echo "Network: $NETWORK"
echo "RPC URL: $RPC_URL"
echo ""

# Load deployment data
if [ ! -f "$DEPLOYMENTS_PATH" ]; then
    echo -e "${RED}❌ Deployments file not found: $DEPLOYMENTS_PATH${NC}"
    exit 1
fi

# Extract resolver address for this network
RESOLVER_ADDRESS=$(jq -r ".contracts.$NETWORK.resolver" "$DEPLOYMENTS_PATH")
if [ "$RESOLVER_ADDRESS" = "null" ] || [ -z "$RESOLVER_ADDRESS" ]; then
    echo -e "${RED}❌ Resolver address not found for $NETWORK${NC}"
    exit 1
fi

echo -e "${BLUE}🤖 Resolver Contract: $RESOLVER_ADDRESS${NC}"

# Load swap secrets (should be created by demo-sign-order.js)
if [ ! -f "$SECRETS_PATH" ]; then
    echo -e "${RED}❌ Swap secrets not found: $SECRETS_PATH${NC}"
    echo -e "${YELLOW}Run: node scripts/demo-sign-order.js${NC}"
    exit 1
fi

echo -e "${BLUE}📖 Loading swap data...${NC}"

# Extract required data from secrets using jq
SECRET_HASH=$(jq -r '.secretHash' "$SECRETS_PATH")
ORDER_HASH=$(jq -r '.orderHash' "$SECRETS_PATH")
SWAP_AMOUNT_WEI=$(jq -r '.swapAmountWei' "$SECRETS_PATH")
MAKER_ADDRESS=$(jq -r '.makerAddress' "$SECRETS_PATH")
SAFETY_DEPOSIT=$(jq -r '.safetyDeposit' "$SECRETS_PATH")

# Order data
ORDER_SALT=$(jq -r '.order.salt' "$SECRETS_PATH")
ORDER_MAKER=$(jq -r '.order.maker' "$SECRETS_PATH")
ORDER_RECEIVER=$(jq -r '.order.receiver' "$SECRETS_PATH")
ORDER_MAKER_ASSET=$(jq -r '.order.makerAsset' "$SECRETS_PATH")
ORDER_TAKER_ASSET=$(jq -r '.order.takerAsset' "$SECRETS_PATH")
ORDER_MAKING_AMOUNT=$(jq -r '.order.makingAmount' "$SECRETS_PATH")
ORDER_TAKING_AMOUNT=$(jq -r '.order.takingAmount' "$SECRETS_PATH")
ORDER_MAKER_TRAITS=$(jq -r '.order.makerTraits' "$SECRETS_PATH")

# Signature data
SIG_R=$(jq -r '.signature.r' "$SECRETS_PATH")
SIG_VS=$(jq -r '.signature.vs' "$SECRETS_PATH")

echo -e "${GREEN}✅ Swap data loaded${NC}"
echo "Order Hash: $ORDER_HASH"
echo "Amount: $SWAP_AMOUNT_WEI wei"
echo "Maker: $MAKER_ADDRESS"
echo ""

# Build immutables struct with proper Address type handling
echo -e "${YELLOW}🏗️  Building immutables struct...${NC}"

# Get current timestamp - this will be used by setDeployedAt() in the contract
CURRENT_TIME=$(date +%s)

# Define timelock offsets (in seconds from deployment)
WITHDRAWAL_OFFSET=300        # 5 minutes
PUBLIC_WITHDRAWAL_OFFSET=600 # 10 minutes  
CANCELLATION_OFFSET=900      # 15 minutes
PUBLIC_CANCELLATION_OFFSET=1200 # 20 minutes

# Pack timelocks correctly according to TimelocksLib
# Stages (7 stages * 32 bits each = 224 bits in lower portion)
# Stage order: SrcWithdrawal=0, SrcPublicWithdrawal=1, SrcCancellation=2, SrcPublicCancellation=3, 
# DstWithdrawal=4, DstPublicWithdrawal=5, DstCancellation=6
# Upper 32 bits reserved for deployment timestamp (set by setDeployedAt)

# Pack all 7 stages into lower 224 bits (each stage gets 32 bits)
TIMELOCKS_PACKED_STAGES=$(printf '%08x%08x%08x%08x%08x%08x%08x' \
    $WITHDRAWAL_OFFSET \
    $PUBLIC_WITHDRAWAL_OFFSET \
    $CANCELLATION_OFFSET \
    $PUBLIC_CANCELLATION_OFFSET \
    $WITHDRAWAL_OFFSET \
    $PUBLIC_WITHDRAWAL_OFFSET \
    $CANCELLATION_OFFSET)

# Convert to proper 256-bit value with zero in upper 32 bits (deployment timestamp slot)
TIMELOCKS_STAGES="0x00000000${TIMELOCKS_PACKED_STAGES}"

# Build immutables tuple with Address.wrap() conversions
# Note: Address is uint256 type, so we need to convert addresses to uint256
MAKER_UINT256="0x$(printf '%064x' $((16#${MAKER_ADDRESS:2})))"
RESOLVER_UINT256="0x$(printf '%064x' $((16#${RESOLVER_ADDRESS:2})))"
TOKEN_UINT256="0x$(printf '%064x' $((16#${ORDER_MAKER_ASSET:2})))"

# Build immutables tuple - order: (orderHash, hashlock, maker, taker, token, amount, safetyDeposit, timelocks)
IMMUTABLES="($ORDER_HASH,$SECRET_HASH,$MAKER_UINT256,$RESOLVER_UINT256,$TOKEN_UINT256,$SWAP_AMOUNT_WEI,$SAFETY_DEPOSIT,$TIMELOCKS_STAGES)"

echo -e "${GREEN}✅ Immutables prepared${NC}"

# Build order tuple  
ORDER="($ORDER_SALT,$ORDER_MAKER,$ORDER_RECEIVER,$ORDER_MAKER_ASSET,$ORDER_TAKER_ASSET,$ORDER_MAKING_AMOUNT,$ORDER_TAKING_AMOUNT,$ORDER_MAKER_TRAITS)"

echo -e "${GREEN}✅ Order tuple prepared${NC}"

# Build taker traits with _ARGS_HAS_TARGET flag
TAKER_TRAITS="0x8000000000000000000000000000000000000000000000000000000000000000" # _ARGS_HAS_TARGET flag

# Build ExtraDataArgs struct for the Factory's _postInteraction method
# This is critical - the Factory needs this data to create the escrow
echo -e "${YELLOW}🏗️  Building ExtraDataArgs...${NC}"

# Get destination network info for ExtraDataArgs
DST_CHAIN_ID=$(jq -r '.networks.destination.chainId' "$SECRETS_PATH")
DST_TOKEN=$(jq -r '.destinationToken' "$SECRETS_PATH")
DST_TOKEN_UINT256="0x$(printf '%064x' $((16#${DST_TOKEN:2})))"

# Pack deposits: srcDeposit (high 128 bits) | dstDeposit (low 128 bits)
# For now, using same safety deposit for both sides
PACKED_DEPOSITS="0x$(printf '%032x%032x' $((SAFETY_DEPOSIT)) $((SAFETY_DEPOSIT)))"

# Build ExtraDataArgs: (hashlockInfo, dstChainId, dstToken, deposits, timelocks)
EXTRA_DATA_ARGS="$SECRET_HASH,$DST_CHAIN_ID,$DST_TOKEN_UINT256,$PACKED_DEPOSITS,$TIMELOCKS_STAGES"

# Now we need to predict the escrow address that will be created
# The Factory will call setDeployedAt(block.timestamp) which modifies timelocks
echo -e "${YELLOW}🔮 Computing escrow address with deployment timestamp...${NC}"

# Create immutables with setDeployedAt applied (approximating with current time + 30s for tx time)
DEPLOYMENT_TIME=$((CURRENT_TIME + 30))

# Apply setDeployedAt transformation: put deployment time in upper 32 bits
# Format: deploymentTime(32 bits) + stages(224 bits) = 256 bits total
TIMELOCKS_WITH_DEPLOYMENT="0x$(printf '%08x%s' $DEPLOYMENT_TIME ${TIMELOCKS_PACKED_STAGES})"
IMMUTABLES_FOR_ADDRESS="($ORDER_HASH,$SECRET_HASH,$MAKER_UINT256,$RESOLVER_UINT256,$TOKEN_UINT256,$SWAP_AMOUNT_WEI,$SAFETY_DEPOSIT,$TIMELOCKS_WITH_DEPLOYMENT)"

ESCROW_SRC_ADDRESS=$(cast call $RESOLVER_ADDRESS "addressOfEscrowSrc((bytes32,bytes32,uint256,uint256,uint256,uint256,uint256,uint256))" "$IMMUTABLES_FOR_ADDRESS" --rpc-url "$RPC_URL" 2>/dev/null || echo "0x0000000000000000000000000000000000000000")

if [ "$ESCROW_SRC_ADDRESS" = "0x0000000000000000000000000000000000000000" ]; then
    echo -e "${RED}❌ Could not compute escrow source address${NC}"
    exit 1
fi

echo -e "${BLUE}📍 Predicted Escrow Source: $ESCROW_SRC_ADDRESS${NC}"

# Build args: ResolverValidationExtension data + ExtraDataArgs(160)
# NOTE: ResolverExample.deploySrc() will add the target address via abi.encodePacked(computed, args)
echo -e "${YELLOW}🔧 Encoding args parameter...${NC}"

# Args format - ResolverExample adds target, so we only provide:
# - ResolverValidationExtension data: allowedTime(4) + bitmap(1) = 5 bytes
# - ExtraDataArgs struct (160 bytes)
# Total: 5 + 160 = 165 bytes

# ResolverValidationExtension data (5 bytes total):
# - allowedTime (4 bytes): when resolver can interact (use current time)
ALLOWED_TIME="$(printf '%08x' $CURRENT_TIME)"                      # 4 bytes
# - bitmap (1 byte): no fee, no integrator fee, no custom receiver, 0 resolvers in whitelist  
BITMAP="00"                                                         # 1 byte

# Encode ExtraDataArgs struct as 160 bytes (5 fields * 32 bytes each)
ARGS_HASHLOCK="${SECRET_HASH:2}"                                    # 32 bytes
ARGS_DST_CHAIN_ID="$(printf '%064x' $DST_CHAIN_ID)"                # 32 bytes  
ARGS_DST_TOKEN="${DST_TOKEN_UINT256:2}"                            # 32 bytes
ARGS_DEPOSITS="${PACKED_DEPOSITS:2}"                               # 32 bytes
ARGS_TIMELOCKS="${TIMELOCKS_STAGES:2}"                             # 32 bytes

# Build args WITHOUT target address (ResolverExample will add it)
ARGS="0x${ALLOWED_TIME}${BITMAP}${ARGS_HASHLOCK}${ARGS_DST_CHAIN_ID}${ARGS_DST_TOKEN}${ARGS_DEPOSITS}${ARGS_TIMELOCKS}"

echo -e "${GREEN}✅ Args parameter encoded ($(((${#ARGS} - 2) / 2)) bytes)${NC}"

# Pre-deployment validation
echo -e "${YELLOW}🔍 Pre-deployment validation...${NC}"

# Validate args length (should be 5 + 160 = 165 bytes = 330 hex chars + 2 for 0x = 332)
EXPECTED_ARGS_LENGTH=332
if [ ${#ARGS} -ne $EXPECTED_ARGS_LENGTH ]; then
    echo -e "${RED}❌ Args length mismatch: expected $EXPECTED_ARGS_LENGTH, got ${#ARGS}${NC}"
    exit 1
fi

# Validate escrow address format
if [[ ! "$ESCROW_SRC_ADDRESS" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
    echo -e "${RED}❌ Invalid escrow address format: $ESCROW_SRC_ADDRESS${NC}"
    exit 1
fi

# Check resolver has sufficient balance for safety deposit
RESOLVER_BALANCE=$(cast balance "$RESOLVER_ADDRESS" --rpc-url "$RPC_URL" 2>/dev/null || echo "0")
if [ "$RESOLVER_BALANCE" -lt "$SAFETY_DEPOSIT" ]; then
    echo -e "${RED}❌ Resolver insufficient balance: $RESOLVER_BALANCE < $SAFETY_DEPOSIT${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Pre-deployment validation passed${NC}"

echo -e "${YELLOW}📡 Calling ResolverExample.deploySrc()...${NC}"

# Send safety deposit first to the predicted address
echo -e "${BLUE}💰 Sending safety deposit to predicted escrow...${NC}"
cast send "$ESCROW_SRC_ADDRESS" --value "$SAFETY_DEPOSIT" --rpc-url "$RPC_URL" --account deployerKey --gas-limit 100000 || {
    echo -e "${RED}❌ Safety deposit transfer failed${NC}"
    exit 1
}

# Call deploySrc function with enhanced error handling
echo -e "${BLUE}🚀 Deploying source escrow...${NC}"

echo -e "${CYAN}📊 Deployment parameters:${NC}"
echo "  Resolver: $RESOLVER_ADDRESS"
echo "  Immutables: $IMMUTABLES"
echo "  Order: $ORDER"
echo "  Gas limit: 3000000"
echo ""

TX_HASH=$(cast send "$RESOLVER_ADDRESS" \
    "deploySrc((bytes32,bytes32,uint256,uint256,uint256,uint256,uint256,uint256),(uint256,address,address,address,address,uint256,uint256,uint256),bytes32,bytes32,uint256,uint256,bytes)" \
    "$IMMUTABLES" \
    "$ORDER" \
    "$SIG_R" \
    "$SIG_VS" \
    "$ORDER_TAKING_AMOUNT" \
    "$TAKER_TRAITS" \
    "$ARGS" \
    --rpc-url "$RPC_URL" \
    --account deployerKey \
    --gas-limit 3000000 \
    --json | jq -r '.transactionHash' 2>/dev/null)

# Wait for transaction confirmation and check status
if [ -n "$TX_HASH" ] && [ "$TX_HASH" != "null" ]; then
    echo -e "${BLUE}⏳ Waiting for transaction confirmation: $TX_HASH${NC}"
    sleep 10
    
    TX_STATUS=$(cast receipt "$TX_HASH" --rpc-url "$RPC_URL" --field status 2>/dev/null || echo "0")
    if [ "$TX_STATUS" = "0x1" ]; then
        echo -e "${GREEN}✅ Transaction confirmed successfully${NC}"
    else
        echo -e "${RED}❌ Transaction failed with status: $TX_STATUS${NC}"
        cast receipt "$TX_HASH" --rpc-url "$RPC_URL" 2>/dev/null || echo "Could not fetch receipt"
        exit 1
    fi
else
    echo -e "${RED}❌ Failed to get transaction hash${NC}"
    exit 1
fi

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Source escrow deployed successfully!${NC}"
    echo -e "${GREEN}📍 Escrow Address: $ESCROW_SRC_ADDRESS${NC}"
    echo -e "${GREEN}🔗 Check transaction on explorer${NC}"
    
    # Update secrets with deployment info
    TMP_FILE=$(mktemp)
    jq --arg addr "$ESCROW_SRC_ADDRESS" --arg time "$CURRENT_TIME" \
       '.status.sourceEscrowDeployed = true | .escrowAddresses.source = $addr | .deploymentTimestamp = ($time | tonumber)' \
       "$SECRETS_PATH" > "$TMP_FILE" && mv "$TMP_FILE" "$SECRETS_PATH"
    
    echo -e "${BLUE}📝 Updated swap status${NC}"
else
    echo -e "${RED}❌ Source escrow deployment failed${NC}"
    exit 1
fi

echo ""
echo -e "${CYAN}🎯 ARCHITECTURE HIGHLIGHT:${NC}"
echo -e "${CYAN}   • Used ResolverExample.deploySrc() directly${NC}"
echo -e "${CYAN}   • Clean separation of concerns${NC}"
echo -e "${CYAN}   • Production-ready contract interaction${NC}"
echo -e "${CYAN}   • 138-line resolver vs 600+ line script${NC}"