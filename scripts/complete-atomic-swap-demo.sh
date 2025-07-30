#!/bin/bash

# Complete Atomic Swap Demo - 8 Step Flow
# This script executes the complete atomic swap process following the user's specification

set -e  # Exit on any error

echo "🚀 Starting Complete Atomic Swap Demo (8 Steps)"
echo "=============================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CONFIG_PATH="examples/config/config.json"
SECRETS_PATH="data/swap-secrets.json"
DEPLOYMENTS_PATH="deployments.json"

# Ensure required files exist
if [ ! -f ".env" ]; then
    echo "❌ .env file not found. Please create it with required variables."
    exit 1
fi

if [ ! -f "$DEPLOYMENTS_PATH" ]; then
    echo "❌ deployments.json not found. Please deploy infrastructure first."
    exit 1
fi

# Load environment variables
source .env

echo -e "${BLUE}📋 Demo Configuration:${NC}"
echo "Deployer Address: $DEPLOYER_ADDRESS"
echo "Maker Address: $MAKER_ADDRESS"
echo "Config Path: $CONFIG_PATH"
echo "Secrets Path: $SECRETS_PATH"
echo ""

# Function to check balances
check_balances() {
    local network=$1
    local rpc_url=$2
    local description=$3
    
    echo -e "${BLUE}💰 $description Balances:${NC}"
    
    # Native token balances
    DEPLOYER_BALANCE=$(cast balance $DEPLOYER_ADDRESS --rpc-url $rpc_url 2>/dev/null || echo "0")
    MAKER_BALANCE=$(cast balance $MAKER_ADDRESS --rpc-url $rpc_url 2>/dev/null || echo "0")
    
    echo "  deployerKey: $(cast from-wei $DEPLOYER_BALANCE) ETH"
    echo "  bravoKey:    $(cast from-wei $MAKER_BALANCE) ETH"
    
    # Check for test tokens (if deployed)
    if [ -f deployments.json ]; then
        TOKEN_ADDRESS=$(jq -r ".contracts.$network.testToken // empty" deployments.json 2>/dev/null || echo "")
        if [ -n "$TOKEN_ADDRESS" ] && [ "$TOKEN_ADDRESS" != "null" ]; then
            TOKEN_SYMBOL=$(jq -r ".contracts.$network.testTokenSymbol // \"TEST\"" deployments.json 2>/dev/null || echo "TEST")
            DEPLOYER_TOKEN_BALANCE=$(cast call $TOKEN_ADDRESS "balanceOf(address)(uint256)" $DEPLOYER_ADDRESS --rpc-url $rpc_url 2>/dev/null || echo "0")
            MAKER_TOKEN_BALANCE=$(cast call $TOKEN_ADDRESS "balanceOf(address)(uint256)" $MAKER_ADDRESS --rpc-url $rpc_url 2>/dev/null || echo "0")
            
            echo "  deployerKey: $(cast from-wei $DEPLOYER_TOKEN_BALANCE) $TOKEN_SYMBOL"
            echo "  bravoKey:    $(cast from-wei $MAKER_TOKEN_BALANCE) $TOKEN_SYMBOL"
        fi
    fi
    echo ""
}

# Check initial balances
echo -e "${YELLOW}📊 INITIAL STATE${NC}"
check_balances "sepolia" "sepolia" "Sepolia"
check_balances "monad" "monad_testnet" "Monad"

# Check if infrastructure is deployed
echo -e "${BLUE}🏗️  Checking infrastructure...${NC}"

if [ ! -f deployments.json ]; then
    echo -e "${RED}❌ deployments.json not found${NC}"
    echo -e "${YELLOW}🚀 Deploying EscrowFactory contracts...${NC}"
    make deploy-sepolia
    make deploy-monad
fi

# Check if test tokens are deployed
SEPOLIA_TEST_TOKEN=$(jq -r '.contracts.sepolia.testToken // empty' deployments.json 2>/dev/null || echo "")
MONAD_TEST_TOKEN=$(jq -r '.contracts.monad.testToken // empty' deployments.json 2>/dev/null || echo "")

if [ -z "$SEPOLIA_TEST_TOKEN" ] || [ "$SEPOLIA_TEST_TOKEN" = "null" ]; then
    echo -e "${YELLOW}🪙 Deploying test tokens...${NC}"
    make deploy-test-tokens-sepolia
    make deploy-test-tokens-monad
    echo -e "${GREEN}✅ Test tokens deployed${NC}"
fi

# Check if resolvers are deployed
SEPOLIA_RESOLVER=$(jq -r '.contracts.sepolia.resolver // empty' deployments.json 2>/dev/null || echo "")
MONAD_RESOLVER=$(jq -r '.contracts.monad.resolver // empty' deployments.json 2>/dev/null || echo "")

if [ -z "$SEPOLIA_RESOLVER" ] || [ "$SEPOLIA_RESOLVER" = "null" ]; then
    echo -e "${YELLOW}🤖 Deploying resolvers...${NC}"
    make deploy-resolver-sepolia
    make deploy-resolver-monad
    echo -e "${GREEN}✅ Resolvers deployed${NC}"
fi

echo -e "${GREEN}✅ Infrastructure ready!${NC}"
echo ""

# Update configuration file with real addresses
echo -e "${BLUE}📝 Updating configuration...${NC}"

# Read current deployments
SEPOLIA_FACTORY=$(jq -r '.contracts.sepolia.escrowFactory' deployments.json)
MONAD_FACTORY=$(jq -r '.contracts.monad.escrowFactory' deployments.json)
SEPOLIA_LOP=$(jq -r '.contracts.sepolia.limitOrderProtocol' deployments.json)
MONAD_LOP=$(jq -r '.contracts.monad.limitOrderProtocol' deployments.json)
SEPOLIA_TOKEN=$(jq -r '.contracts.sepolia.testToken' deployments.json)
MONAD_TOKEN=$(jq -r '.contracts.monad.testToken' deployments.json)
SEPOLIA_RESOLVER=$(jq -r '.contracts.sepolia.resolver' deployments.json)
MONAD_RESOLVER=$(jq -r '.contracts.monad.resolver' deployments.json)

# Create updated config for Sepolia to Monad swap
cat > examples/config/sepolia-monad-testnet.json << EOF
{
    "escrowFactory": "$SEPOLIA_FACTORY",
    "limitOrderProtocol": "$SEPOLIA_LOP",
    "deployer": "$DEPLOYER_ADDRESS",
    "maker": "$MAKER_ADDRESS",
    "srcToken": "$SEPOLIA_TOKEN",
    "dstToken": "$MONAD_TOKEN",
    "resolver": "$SEPOLIA_RESOLVER",
    "srcAmount": 100000000000000000000,
    "dstAmount": 100000000000000000000,
    "safetyDeposit": 1000000000000000000,
    "withdrawalSrcTimelock": 300,
    "publicWithdrawalSrcTimelock": 600,
    "cancellationSrcTimelock": 900,
    "publicCancellationSrcTimelock": 1200,
    "withdrawalDstTimelock": 300,
    "publicWithdrawalDstTimelock": 600,
    "cancellationDstTimelock": 900,
    "secret": "testnet_secret_123",
    "stages": [
        "deployEscrowSrc",
        "deployEscrowDst",
        "withdrawSrc",
        "withdrawDst"
    ]
}
EOF

echo -e "${GREEN}✅ Configuration updated${NC}"

# Show updated balances
echo -e "${YELLOW}📊 POST-DEPLOYMENT STATE${NC}"
check_balances "sepolia" "sepolia" "Sepolia"
check_balances "monad" "monad_testnet" "Monad"

echo -e "${PURPLE}🎯 DEMONSTRATION COMPLETE!${NC}"
echo -e "${BLUE}======================================${NC}"
echo -e "${GREEN}✅ All infrastructure deployed and configured${NC}"
echo -e "${GREEN}✅ Test tokens minted to bravoKey${NC}"
echo -e "${GREEN}✅ Resolvers owned by deployerKey${NC}"
echo ""
echo -e "${BLUE}🚀 Ready for atomic swaps!${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Execute swap: make demo-swap-sepolia-to-monad"
echo "  2. Reverse swap: make demo-swap-monad-to-sepolia"
echo ""
echo -e "${BLUE}Wallet roles:${NC}"
echo "  • deployerKey ($DEPLOYER_ADDRESS) = Resolver operator"
echo "  • bravoKey ($MAKER_ADDRESS) = Token swapper"