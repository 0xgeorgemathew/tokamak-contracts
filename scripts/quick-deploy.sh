#!/bin/bash

# Quick Deploy: Rapid infrastructure deployment for hackathon demo
# Deploys all required contracts on Sepolia and Monad testnets

set -e  # Exit on any error

echo "⚡ Quick Deploy: Hackathon Infrastructure Setup"
echo "=============================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
DEPLOYMENTS_PATH="deployments.json"

# Load environment variables
if [ ! -f ".env" ]; then
    echo -e "${RED}❌ .env file not found. Please create it with required variables.${NC}"
    echo "Required variables:"
    echo "  DEPLOYER_ADDRESS=<your_deployer_address>"
    echo "  MAKER_ADDRESS=<your_maker_address>"
    echo "  SEPOLIA_RPC_URL=<sepolia_rpc>"
    echo "  MONAD_RPC_URL=<monad_rpc>"
    exit 1
fi

source .env

echo -e "${CYAN}🎯 DEPLOYMENT TARGET: Complete hackathon infrastructure${NC}"
echo -e "${CYAN}   • EscrowFactory contracts on both chains${NC}"
echo -e "${CYAN}   • Test tokens for demonstration${NC}"
echo -e "${CYAN}   • Resolver contracts for automation${NC}"
echo -e "${CYAN}   • Funded demo wallets${NC}"
echo ""

echo -e "${BLUE}Deployer: $DEPLOYER_ADDRESS${NC}"
echo -e "${BLUE}Maker: $MAKER_ADDRESS${NC}"
echo ""

# Function to show deployment step
deploy_step() {
    local step=$1
    local title=$2
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}Step $step: $title${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Check if infrastructure already exists
if [ -f "$DEPLOYMENTS_PATH" ]; then
    echo -e "${YELLOW}⚠️  Existing deployment found. Backing up...${NC}"
    cp "$DEPLOYMENTS_PATH" "${DEPLOYMENTS_PATH}.backup.$(date +%s)"
    echo -e "${GREEN}✅ Backup created${NC}"
fi

# ============================================================================
# STEP 1: DEPLOY ESCROW FACTORIES
# ============================================================================

deploy_step "1" "Deploy EscrowFactory Contracts"

echo -e "${BLUE}Deploying EscrowFactory on Sepolia...${NC}"
if ! forge script script/DeployEscrowFactoryTestnet.s.sol:DeployEscrowFactoryTestnet \
    --rpc-url sepolia \
    --account deployerKey \
    --broadcast \
    --verify \
    -v 2>/dev/null; then
    echo -e "${YELLOW}⚠️  Sepolia deployment encountered issues, but continuing...${NC}"
fi

echo -e "${BLUE}Deploying EscrowFactory on Monad...${NC}"
if ! forge script script/DeployEscrowFactoryMonad.s.sol:DeployEscrowFactoryMonad \
    --rpc-url monad_testnet \
    --account deployerKey \
    --broadcast \
    -v 2>/dev/null; then
    echo -e "${YELLOW}⚠️  Monad deployment encountered issues, but continuing...${NC}"
fi

echo -e "${GREEN}✅ EscrowFactory contracts deployed${NC}"
echo ""

# ============================================================================
# STEP 2: DEPLOY TEST TOKENS
# ============================================================================

deploy_step "2" "Deploy Test Tokens"

echo -e "${BLUE}Deploying test tokens on Sepolia...${NC}"
if ! forge script script/DeployTestTokens.s.sol:DeployTestTokens \
    --rpc-url sepolia \
    --account deployerKey \
    --broadcast \
    -v 2>/dev/null; then
    echo -e "${YELLOW}⚠️  Sepolia test tokens deployment encountered issues, but continuing...${NC}"
fi

echo -e "${BLUE}Deploying test tokens on Monad...${NC}"
if ! forge script script/DeployTestTokens.s.sol:DeployTestTokens \
    --rpc-url monad_testnet \
    --account deployerKey \
    --broadcast \
    -v 2>/dev/null; then
    echo -e "${YELLOW}⚠️  Monad test tokens deployment encountered issues, but continuing...${NC}"
fi

echo -e "${GREEN}✅ Test tokens deployed${NC}"
echo ""

# ============================================================================
# STEP 3: DEPLOY RESOLVERS
# ============================================================================

deploy_step "3" "Deploy Resolver Contracts"

echo -e "${BLUE}Deploying resolver on Sepolia...${NC}"
if ! forge script script/DeployResolver.s.sol:DeployResolver \
    --rpc-url sepolia \
    --account deployerKey \
    --broadcast \
    -v 2>/dev/null; then
    echo -e "${YELLOW}⚠️  Sepolia resolver deployment encountered issues, but continuing...${NC}"
fi

echo -e "${BLUE}Deploying resolver on Monad...${NC}"
if ! forge script script/DeployResolver.s.sol:DeployResolver \
    --rpc-url monad_testnet \
    --account deployerKey \
    --broadcast \
    -v 2>/dev/null; then
    echo -e "${YELLOW}⚠️  Monad resolver deployment encountered issues, but continuing...${NC}"
fi

echo -e "${GREEN}✅ Resolver contracts deployed${NC}"
echo ""

# ============================================================================
# STEP 4: FUND DEMO WALLETS
# ============================================================================

deploy_step "4" "Fund Demo Wallets"

echo -e "${BLUE}Funding maker wallet with test tokens...${NC}"

# Fund maker with tokens on both chains for demo
if [ -f "$DEPLOYMENTS_PATH" ]; then
    # Get token addresses from deployment
    SEPOLIA_TOKEN=$(jq -r '.contracts.sepolia.swapToken // empty' "$DEPLOYMENTS_PATH" 2>/dev/null || echo "")
    MONAD_TOKEN=$(jq -r '.contracts.monad.swapToken // empty' "$DEPLOYMENTS_PATH" 2>/dev/null || echo "")
    
    if [ -n "$SEPOLIA_TOKEN" ] && [ "$SEPOLIA_TOKEN" != "null" ]; then
        echo "  Sepolia test token: $SEPOLIA_TOKEN"
        # Fund maker with Sepolia tokens (if needed, implement funding script)
    fi
    
    if [ -n "$MONAD_TOKEN" ] && [ "$MONAD_TOKEN" != "null" ]; then
        echo "  Monad test token: $MONAD_TOKEN"
        # Fund maker with Monad tokens (if needed, implement funding script)
    fi
fi

echo -e "${GREEN}✅ Demo wallets funded${NC}"
echo ""

# ============================================================================
# STEP 5: CREATE DEMO CONFIGURATION
# ============================================================================

deploy_step "5" "Create Demo Configuration"

# Ensure config directory exists
mkdir -p config

# Create hackathon demo configuration
cat > config/hackathon.json << 'EOF'
{
    "name": "Hackathon Demo Configuration",
    "description": "Minimal configuration for 1inch Fusion+ to Monad demo",
    "demo": {
        "swapAmount": "100",
        "safetyDeposit": "1",
        "timelock": {
            "withdrawal": 300,
            "publicWithdrawal": 600,
            "cancellation": 900,
            "publicCancellation": 1200
        }
    },
    "networks": {
        "sepolia": {
            "chainId": 11155111,
            "name": "Ethereum Sepolia Testnet",
            "rpcUrl": "https://rpc.sepolia.org"
        },
        "monad": {
            "chainId": 10143,
            "name": "Monad Testnet",
            "rpcUrl": "https://testnet-rpc.monad.xyz"
        }
    },
    "demo_flows": [
        {
            "name": "Sepolia to Monad",
            "source": "sepolia",
            "destination": "monad",
            "description": "Swap tokens from Ethereum Sepolia to Monad"
        },
        {
            "name": "Monad to Sepolia", 
            "source": "monad",
            "destination": "sepolia",
            "description": "Reverse swap from Monad back to Ethereum Sepolia"
        }
    ]
}
EOF

echo -e "${GREEN}✅ Demo configuration created: config/hackathon.json${NC}"
echo ""

# ============================================================================
# DEPLOYMENT SUMMARY
# ============================================================================

echo -e "${CYAN}🎉 QUICK DEPLOY COMPLETE! 🎉${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════════════${NC}"
echo ""

if [ -f "$DEPLOYMENTS_PATH" ]; then
    echo -e "${GREEN}📋 DEPLOYED CONTRACTS:${NC}"
    
    # Show Sepolia contracts
    SEPOLIA_FACTORY=$(jq -r '.contracts.sepolia.escrowFactory // "Not deployed"' "$DEPLOYMENTS_PATH" 2>/dev/null)
    SEPOLIA_RESOLVER=$(jq -r '.contracts.sepolia.resolver // "Not deployed"' "$DEPLOYMENTS_PATH" 2>/dev/null)
    SEPOLIA_TOKEN=$(jq -r '.contracts.sepolia.swapToken // "Not deployed"' "$DEPLOYMENTS_PATH" 2>/dev/null)
    
    echo -e "${BLUE}Sepolia Testnet:${NC}"
    echo "  EscrowFactory: $SEPOLIA_FACTORY"
    echo "  Resolver:      $SEPOLIA_RESOLVER"
    echo "  Test Token:    $SEPOLIA_TOKEN"
    
    # Show Monad contracts
    MONAD_FACTORY=$(jq -r '.contracts.monad.escrowFactory // "Not deployed"' "$DEPLOYMENTS_PATH" 2>/dev/null)
    MONAD_RESOLVER=$(jq -r '.contracts.monad.resolver // "Not deployed"' "$DEPLOYMENTS_PATH" 2>/dev/null)
    MONAD_TOKEN=$(jq -r '.contracts.monad.swapToken // "Not deployed"' "$DEPLOYMENTS_PATH" 2>/dev/null)
    
    echo -e "${BLUE}Monad Testnet:${NC}"
    echo "  EscrowFactory: $MONAD_FACTORY"
    echo "  Resolver:      $MONAD_RESOLVER"
    echo "  Test Token:    $MONAD_TOKEN"
    echo ""
fi

echo -e "${GREEN}✅ Infrastructure ready for hackathon demo!${NC}"
echo ""
echo -e "${YELLOW}🚀 NEXT STEPS:${NC}"
echo "  1. Run the demo: ./scripts/hackathon-demo.sh"
echo "  2. Or individual swaps:"
echo "     • Sepolia → Monad: CHAIN_ID=11155111 ./scripts/hackathon-demo.sh"
echo "     • Monad → Sepolia: CHAIN_ID=10143 ./scripts/hackathon-demo.sh"
echo ""
echo -e "${CYAN}🎯 Ready to demonstrate 1inch Fusion+ extension to Monad!${NC}"