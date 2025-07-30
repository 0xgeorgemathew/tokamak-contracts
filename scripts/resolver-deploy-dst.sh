#!/bin/bash

# Resolver Deploy Destination: Direct ResolverExample.deployDst() call
# This script demonstrates the correct architecture using ResolverExample contract directly

set -e  # Exit on any error

echo "🎯 Resolver Deploy Destination: Direct Contract Call"
echo "================================================="

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

# Get chain ID from environment (default to Monad for destination)
CHAIN_ID=${CHAIN_ID:-10143}

# Determine network and RPC
if [ "$CHAIN_ID" = "11155111" ]; then
    NETWORK="sepolia"
    RPC_URL=${SEPOLIA_RPC_URL:-"sepolia"}
    DEST_NETWORK="monad"
elif [ "$CHAIN_ID" = "10143" ]; then
    NETWORK="monad"
    RPC_URL=${MONAD_RPC_URL:-"monad_testnet"}
    DEST_NETWORK="sepolia"
else
    echo -e "${RED}❌ Unsupported chain ID: $CHAIN_ID${NC}"
    exit 1
fi

echo -e "${CYAN}📋 Configuration:${NC}"
echo "Chain ID: $CHAIN_ID"
echo "Network: $NETWORK (destination chain)"
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

# Get destination token address
DST_TOKEN_ADDRESS=$(jq -r ".contracts.$NETWORK.swapToken" "$DEPLOYMENTS_PATH")
if [ "$DST_TOKEN_ADDRESS" = "null" ] || [ -z "$DST_TOKEN_ADDRESS" ]; then
    echo -e "${RED}❌ Destination token address not found for $NETWORK${NC}"
    exit 1
fi

echo -e "${BLUE}🤖 Resolver Contract: $RESOLVER_ADDRESS${NC}"
echo -e "${BLUE}🪙 Destination Token: $DST_TOKEN_ADDRESS${NC}"

# Load swap secrets (should be created by demo-sign-order.js and updated by resolver-deploy-src.sh)
if [ ! -f "$SECRETS_PATH" ]; then
    echo -e "${RED}❌ Swap secrets not found: $SECRETS_PATH${NC}"
    echo -e "${YELLOW}Run: node scripts/demo-sign-order.js${NC}"
    exit 1
fi

# Check if source escrow was deployed
SOURCE_DEPLOYED=$(jq -r '.status.sourceEscrowDeployed // false' "$SECRETS_PATH")
if [ "$SOURCE_DEPLOYED" != "true" ]; then
    echo -e "${RED}❌ Source escrow not deployed yet${NC}"
    echo -e "${YELLOW}Run: ./scripts/resolver-deploy-src.sh first${NC}"
    exit 1
fi

echo -e "${BLUE}📖 Loading swap data...${NC}"

# Extract required data from secrets using jq
SECRET_HASH=$(jq -r '.secretHash' "$SECRETS_PATH")
ORDER_HASH=$(jq -r '.orderHash' "$SECRETS_PATH")
SWAP_AMOUNT_WEI=$(jq -r '.swapAmountWei' "$SECRETS_PATH")
MAKER_ADDRESS=$(jq -r '.makerAddress' "$SECRETS_PATH")
SAFETY_DEPOSIT=$(jq -r '.safetyDeposit' "$SECRETS_PATH")
DEPLOYMENT_TIMESTAMP=$(jq -r '.deploymentTimestamp // 0' "$SECRETS_PATH")

echo -e "${GREEN}✅ Swap data loaded${NC}"
echo "Order Hash: $ORDER_HASH"
echo "Amount: $SWAP_AMOUNT_WEI wei"
echo "Maker: $MAKER_ADDRESS"
echo "Source deployed at: $DEPLOYMENT_TIMESTAMP"
echo ""

# Build destination immutables struct
echo -e "${YELLOW}🏗️  Building destination immutables struct...${NC}"

# Use the same timelock structure but for destination chain
CURRENT_TIME=$(date +%s)
WITHDRAWAL_TIME=$((CURRENT_TIME + 300))       # 5 minutes
PUBLIC_WITHDRAWAL_TIME=$((CURRENT_TIME + 600)) # 10 minutes  
CANCELLATION_TIME=$((CURRENT_TIME + 900))     # 15 minutes
PUBLIC_CANCELLATION_TIME=$((CURRENT_TIME + 1200)) # 20 minutes

# Pack timelocks for destination
DST_TIMELOCKS="0x$(printf '%08x%08x%08x%08x%016x' $WITHDRAWAL_TIME $PUBLIC_WITHDRAWAL_TIME $CANCELLATION_TIME $PUBLIC_CANCELLATION_TIME $CURRENT_TIME)"

# Build destination immutables tuple
# (orderHash, amount, maker, taker, token, hashlock, safetyDeposit, timelocks)
DST_IMMUTABLES="($ORDER_HASH,$SWAP_AMOUNT_WEI,$MAKER_ADDRESS,$RESOLVER_ADDRESS,$DST_TOKEN_ADDRESS,$SECRET_HASH,$SAFETY_DEPOSIT,$DST_TIMELOCKS)"

echo -e "${GREEN}✅ Destination immutables prepared${NC}"

# Calculate source cancellation timestamp (from deployment timestamp + cancellation period)
SRC_CANCELLATION_TIMESTAMP=$((DEPLOYMENT_TIMESTAMP + 900)) # 15 minutes after source deployment

echo -e "${BLUE}⏰ Source cancellation timestamp: $SRC_CANCELLATION_TIMESTAMP${NC}"

# Compute destination escrow address
echo -e "${BLUE}🧮 Computing destination escrow address...${NC}"

# This calls the factory's addressOfEscrowDst function through the resolver
ESCROW_DST_ADDRESS=$(cast call "$RESOLVER_ADDRESS" "addressOfEscrowDst((bytes32,uint256,address,address,address,bytes32,uint256,uint256))" "$DST_IMMUTABLES" --rpc-url "$RPC_URL" 2>/dev/null || echo "0x0000000000000000000000000000000000000000")

if [ "$ESCROW_DST_ADDRESS" = "0x0000000000000000000000000000000000000000" ]; then
    # Try to compute via factory directly
    FACTORY_ADDRESS=$(jq -r ".contracts.$NETWORK.escrowFactory" "$DEPLOYMENTS_PATH")
    if [ "$FACTORY_ADDRESS" != "null" ] && [ -n "$FACTORY_ADDRESS" ]; then
        echo -e "${YELLOW}⚠️  Trying factory directly...${NC}"
        ESCROW_DST_ADDRESS=$(cast call "$FACTORY_ADDRESS" "addressOfEscrowDst((bytes32,uint256,address,address,address,bytes32,uint256,uint256))" "$DST_IMMUTABLES" --rpc-url "$RPC_URL" 2>/dev/null || echo "0x0000000000000000000000000000000000000000")
    fi
fi

if [ "$ESCROW_DST_ADDRESS" = "0x0000000000000000000000000000000000000000" ]; then
    echo -e "${RED}❌ Could not compute destination escrow address${NC}"
    exit 1
fi

echo -e "${BLUE}📍 Computed Escrow Destination: $ESCROW_DST_ADDRESS${NC}"

# Fund resolver with destination tokens
echo -e "${YELLOW}💰 Funding resolver with destination tokens...${NC}"

# Check if resolver needs tokens
RESOLVER_BALANCE=$(cast call "$DST_TOKEN_ADDRESS" "balanceOf(address)(uint256)" "$RESOLVER_ADDRESS" --rpc-url "$RPC_URL" 2>/dev/null || echo "0")

if [ "$RESOLVER_BALANCE" = "0" ] || [ -z "$RESOLVER_BALANCE" ]; then
    echo -e "${BLUE}🪙 Minting tokens to resolver for demo...${NC}"
    # For demo purposes, try to mint tokens directly (if possible)
    # This assumes test tokens have a mint function
    cast send "$DST_TOKEN_ADDRESS" "mint(address,uint256)" "$RESOLVER_ADDRESS" "$SWAP_AMOUNT_WEI" \
        --rpc-url "$RPC_URL" --account deployerKey 2>/dev/null || {
        echo -e "${YELLOW}⚠️  Could not mint tokens, assuming resolver has sufficient balance${NC}"
    }
fi

# Approve tokens to factory
FACTORY_ADDRESS=$(jq -r ".contracts.$NETWORK.escrowFactory" "$DEPLOYMENTS_PATH")
echo -e "${BLUE}✅ Approving tokens to factory...${NC}"

# Use resolver's arbitraryCalls to approve tokens
APPROVE_DATA=$(cast calldata "approve(address,uint256)" "$FACTORY_ADDRESS" "$SWAP_AMOUNT_WEI")

cast send "$RESOLVER_ADDRESS" \
    "arbitraryCalls(address[],bytes[])" \
    "[$DST_TOKEN_ADDRESS]" \
    "[$APPROVE_DATA]" \
    --rpc-url "$RPC_URL" \
    --account deployerKey \
    --gas-limit 500000 || {
    echo -e "${YELLOW}⚠️  Token approval may have failed, continuing...${NC}"
}

echo -e "${YELLOW}📡 Calling ResolverExample.deployDst()...${NC}"

# Call deployDst function with safety deposit
cast send "$RESOLVER_ADDRESS" \
    "deployDst((bytes32,uint256,address,address,address,bytes32,uint256,uint256),uint256)" \
    "$DST_IMMUTABLES" \
    "$SRC_CANCELLATION_TIMESTAMP" \
    --value "$SAFETY_DEPOSIT" \
    --rpc-url "$RPC_URL" \
    --account deployerKey \
    --gas-limit 2000000

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Destination escrow deployed successfully!${NC}"
    echo -e "${GREEN}📍 Escrow Address: $ESCROW_DST_ADDRESS${NC}"
    echo -e "${GREEN}🔗 Check transaction on explorer${NC}"
    
    # Update secrets with deployment info
    TMP_FILE=$(mktemp)
    jq --arg addr "$ESCROW_DST_ADDRESS" --arg time "$CURRENT_TIME" \
       '.status.destinationEscrowDeployed = true | .escrowAddresses.destination = $addr | .destinationDeploymentTimestamp = ($time | tonumber)' \
       "$SECRETS_PATH" > "$TMP_FILE" && mv "$TMP_FILE" "$SECRETS_PATH"
    
    echo -e "${BLUE}📝 Updated swap status${NC}"
else
    echo -e "${RED}❌ Destination escrow deployment failed${NC}"
    exit 1
fi

echo ""
echo -e "${CYAN}🎯 ARCHITECTURE HIGHLIGHT:${NC}"
echo -e "${CYAN}   • Used ResolverExample.deployDst() directly${NC}"
echo -e "${CYAN}   • Cross-chain coordination via off-chain scripts${NC}"
echo -e "${CYAN}   • Production-ready contract interaction${NC}"
echo -e "${CYAN}   • Clean separation from orchestration logic${NC}"

echo ""
echo -e "${GREEN}🚀 Both escrows now deployed! Ready for atomic withdrawals.${NC}"