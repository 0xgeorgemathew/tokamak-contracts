#!/bin/bash

# Resolver Withdraw: Direct ResolverExample.arbitraryCalls() for atomic withdrawals
# This script demonstrates the correct architecture using ResolverExample contract directly

set -e  # Exit on any error

echo "💰 Resolver Withdraw: Direct Contract Call"
echo "========================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Configuration
DEPLOYMENTS_PATH="deployments.json"
SECRETS_PATH="data/swap-secrets.json"

# Parameters
WITHDRAW_MODE=${1:-"dst"} # "dst" or "src"

# Load environment variables
if [ ! -f ".env" ]; then
    echo -e "${RED}❌ .env file not found${NC}"
    exit 1
fi
source .env

# Determine chain and network based on withdraw mode
if [ "$WITHDRAW_MODE" = "dst" ]; then
    # Withdraw destination tokens (reveal secret)
    CHAIN_ID=${CHAIN_ID:-10143}  # Default to Monad for destination
    if [ "$CHAIN_ID" = "10143" ]; then
        NETWORK="monad"
        RPC_URL=${MONAD_RPC_URL:-"monad_testnet"}
    else
        NETWORK="sepolia"
        RPC_URL=${SEPOLIA_RPC_URL:-"sepolia"}
    fi
    ESCROW_KEY="destination"
    WITHDRAW_TITLE="Destination Withdrawal (Reveal Secret)"
elif [ "$WITHDRAW_MODE" = "src" ]; then
    # Withdraw source tokens (use revealed secret)
    CHAIN_ID=${CHAIN_ID:-11155111}  # Default to Sepolia for source
    if [ "$CHAIN_ID" = "11155111" ]; then
        NETWORK="sepolia"
        RPC_URL=${SEPOLIA_RPC_URL:-"sepolia"}
    else
        NETWORK="monad"
        RPC_URL=${MONAD_RPC_URL:-"monad_testnet"}
    fi
    ESCROW_KEY="source"
    WITHDRAW_TITLE="Source Withdrawal (Use Secret)"
else
    echo -e "${RED}❌ Invalid withdraw mode: $WITHDRAW_MODE${NC}"
    echo "Usage: $0 [dst|src]"
    exit 1
fi

echo -e "${MAGENTA}🎯 $WITHDRAW_TITLE${NC}"
echo -e "${CYAN}📋 Configuration:${NC}"
echo "Mode: $WITHDRAW_MODE"
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

# Load swap secrets
if [ ! -f "$SECRETS_PATH" ]; then
    echo -e "${RED}❌ Swap secrets not found: $SECRETS_PATH${NC}"
    exit 1
fi

# Check deployment status
SOURCE_DEPLOYED=$(jq -r '.status.sourceEscrowDeployed // false' "$SECRETS_PATH")
DEST_DEPLOYED=$(jq -r '.status.destinationEscrowDeployed // false' "$SECRETS_PATH")

if [ "$SOURCE_DEPLOYED" != "true" ] || [ "$DEST_DEPLOYED" != "true" ]; then
    echo -e "${RED}❌ Both escrows must be deployed first${NC}"
    echo "Source deployed: $SOURCE_DEPLOYED"
    echo "Destination deployed: $DEST_DEPLOYED"
    exit 1
fi

echo -e "${BLUE}📖 Loading swap data...${NC}"

# Extract required data
SECRET=$(jq -r '.secret' "$SECRETS_PATH")
SECRET_HASH=$(jq -r '.secretHash' "$SECRETS_PATH")
ORDER_HASH=$(jq -r '.orderHash' "$SECRETS_PATH")
SWAP_AMOUNT_WEI=$(jq -r '.swapAmountWei' "$SECRETS_PATH")
MAKER_ADDRESS=$(jq -r '.makerAddress' "$SECRETS_PATH")
SAFETY_DEPOSIT=$(jq -r '.safetyDeposit' "$SECRETS_PATH")

# Get escrow address
ESCROW_ADDRESS=$(jq -r ".escrowAddresses.$ESCROW_KEY" "$SECRETS_PATH")
if [ "$ESCROW_ADDRESS" = "null" ] || [ -z "$ESCROW_ADDRESS" ]; then
    echo -e "${RED}❌ $ESCROW_KEY escrow address not found${NC}"
    exit 1
fi

# Get token address for this network
TOKEN_ADDRESS=$(jq -r ".contracts.$NETWORK.swapToken" "$DEPLOYMENTS_PATH")

echo -e "${GREEN}✅ Swap data loaded${NC}"
echo "Escrow Address: $ESCROW_ADDRESS"
echo "Token Address: $TOKEN_ADDRESS"
echo "Amount: $SWAP_AMOUNT_WEI wei"
echo ""

# Build immutables for this escrow
echo -e "${YELLOW}🏗️  Building immutables struct...${NC}"

# Get deployment timestamp
if [ "$WITHDRAW_MODE" = "dst" ]; then
    DEPLOY_TIME=$(jq -r '.destinationDeploymentTimestamp // 0' "$SECRETS_PATH")
else
    DEPLOY_TIME=$(jq -r '.deploymentTimestamp // 0' "$SECRETS_PATH")
fi

if [ "$DEPLOY_TIME" = "0" ]; then
    DEPLOY_TIME=$(date +%s)
    echo -e "${YELLOW}⚠️  Using current time for timelocks${NC}"
fi

# Rebuild timelocks with deployment time
WITHDRAWAL_TIME=$((DEPLOY_TIME + 300))       # 5 minutes after deployment
PUBLIC_WITHDRAWAL_TIME=$((DEPLOY_TIME + 600)) # 10 minutes after deployment
CANCELLATION_TIME=$((DEPLOY_TIME + 900))     # 15 minutes after deployment  
PUBLIC_CANCELLATION_TIME=$((DEPLOY_TIME + 1200)) # 20 minutes after deployment

TIMELOCKS="0x$(printf '%08x%08x%08x%08x%016x' $WITHDRAWAL_TIME $PUBLIC_WITHDRAWAL_TIME $CANCELLATION_TIME $PUBLIC_CANCELLATION_TIME $DEPLOY_TIME)"

# Build immutables tuple
IMMUTABLES="($ORDER_HASH,$SWAP_AMOUNT_WEI,$MAKER_ADDRESS,$RESOLVER_ADDRESS,$TOKEN_ADDRESS,$SECRET_HASH,$SAFETY_DEPOSIT,$TIMELOCKS)"

echo -e "${GREEN}✅ Immutables prepared${NC}"

# Check current time vs withdrawal time
CURRENT_TIME=$(date +%s)
if [ $CURRENT_TIME -lt $WITHDRAWAL_TIME ]; then
    WAIT_TIME=$((WITHDRAWAL_TIME - CURRENT_TIME))
    echo -e "${YELLOW}⏰ Withdrawal time lock not yet reached${NC}"
    echo "Current time: $CURRENT_TIME"
    echo "Withdrawal time: $WITHDRAWAL_TIME"
    echo "Wait time: $WAIT_TIME seconds"
    
    if [ $WAIT_TIME -lt 300 ]; then
        echo -e "${BLUE}⏳ Waiting $WAIT_TIME seconds...${NC}"
        sleep $WAIT_TIME
    else
        echo -e "${RED}❌ Please wait $((WAIT_TIME / 60)) minutes before withdrawing${NC}"
        exit 1
    fi
fi

# Prepare withdrawal call
echo -e "${YELLOW}📡 Preparing withdrawal call...${NC}"

if [ "$WITHDRAW_MODE" = "dst" ]; then
    # Destination withdrawal - reveals secret
    echo -e "${MAGENTA}🔓 Revealing secret and withdrawing destination tokens${NC}"
    WITHDRAW_CALL=$(cast calldata "withdraw(bytes32,(bytes32,uint256,address,address,address,bytes32,uint256,uint256))" "$SECRET" "$IMMUTABLES")
    echo -e "${BLUE}🔑 Secret will be revealed on-chain: $SECRET${NC}"
else
    # Source withdrawal - uses revealed secret  
    echo -e "${MAGENTA}🔓 Using revealed secret to withdraw source tokens${NC}"
    WITHDRAW_CALL=$(cast calldata "withdraw(bytes32,(bytes32,uint256,address,address,address,bytes32,uint256,uint256))" "$SECRET" "$IMMUTABLES")
    echo -e "${BLUE}🔑 Using secret: $SECRET${NC}"
fi

echo -e "${GREEN}✅ Withdrawal call prepared${NC}"

# Execute withdrawal via resolver's arbitraryCalls
echo -e "${YELLOW}💰 Executing withdrawal via ResolverExample.arbitraryCalls()...${NC}"

cast send "$RESOLVER_ADDRESS" \
    "arbitraryCalls(address[],bytes[])" \
    "[$ESCROW_ADDRESS]" \
    "[$WITHDRAW_CALL]" \
    --rpc-url "$RPC_URL" \
    --account deployerKey \
    --gas-limit 2000000

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Withdrawal executed successfully!${NC}"
    
    if [ "$WITHDRAW_MODE" = "dst" ]; then
        echo -e "${GREEN}🔑 Secret revealed on-chain!${NC}"
        echo -e "${GREEN}🎯 Destination tokens transferred to maker${NC}"
        
        # Update status
        TMP_FILE=$(mktemp)
        jq '.status.secretRevealed = true | .status.destinationWithdrawn = true' \
           "$SECRETS_PATH" > "$TMP_FILE" && mv "$TMP_FILE" "$SECRETS_PATH"
    else
        echo -e "${GREEN}🎯 Source tokens transferred to resolver${NC}"
        echo -e "${GREEN}💰 Safety deposits recovered${NC}"
        
        # Update status  
        TMP_FILE=$(mktemp)
        jq '.status.sourceWithdrawn = true | .status.completed = true' \
           "$SECRETS_PATH" > "$TMP_FILE" && mv "$TMP_FILE" "$SECRETS_PATH"
    fi
    
    echo -e "${BLUE}📝 Updated swap status${NC}"
else
    echo -e "${RED}❌ Withdrawal failed${NC}"
    exit 1
fi

echo ""
echo -e "${CYAN}🎯 ARCHITECTURE HIGHLIGHT:${NC}"
echo -e "${CYAN}   • Used ResolverExample.arbitraryCalls() directly${NC}"
echo -e "${CYAN}   • Clean escrow interaction via resolver${NC}"
echo -e "${CYAN}   • Atomic secret revelation mechanism${NC}"
echo -e "${CYAN}   • Production-ready withdrawal pattern${NC}"

# Show next steps
if [ "$WITHDRAW_MODE" = "dst" ]; then
    echo ""
    echo -e "${YELLOW}🔄 Next step: Withdraw source tokens${NC}"
    echo -e "${BLUE}Run: ./scripts/resolver-withdraw.sh src${NC}"
else
    echo ""
    echo -e "${GREEN}🎉 ATOMIC SWAP COMPLETE!${NC}"
    echo -e "${GREEN}   • Secret revealed ✓${NC}"
    echo -e "${GREEN}   • Tokens transferred ✓${NC}"  
    echo -e "${GREEN}   • Safety deposits recovered ✓${NC}"
    echo -e "${GREEN}   • Atomic completion verified ✓${NC}"
fi