#!/bin/bash

# Complete Contract Redeployment Script
# Redeploys all contracts except tokens on both Sepolia and Monad testnet

set -e  # Exit on any error

echo "🚀 Starting Complete Contract Redeployment"
echo "=========================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
DEPLOYMENTS_PATH="deployments.json"

# Ensure required files exist
if [ ! -f ".env" ]; then
    echo "❌ .env file not found. Please create it with required variables."
    exit 1
fi

if [ ! -f "$DEPLOYMENTS_PATH" ]; then
    echo "❌ deployments.json not found. Please ensure it exists with token addresses."
    exit 1
fi

# Load environment variables
source .env

echo -e "${BLUE}📋 Redeployment Configuration:${NC}"
echo "Deployer Address: $DEPLOYER_ADDRESS"
echo "Preserving existing token addresses"
echo ""

# Backup current deployments
echo -e "${YELLOW}📦 Backing up current deployments...${NC}"
cp "$DEPLOYMENTS_PATH" "${DEPLOYMENTS_PATH}.backup.$(date +%s)"
echo "✅ Backup created"
echo ""

# =======================================================================
# Phase 1: Deploy Limit Order Protocol on both chains
# =======================================================================

echo -e "${YELLOW}Phase 1: Deploying Limit Order Protocol${NC}"
echo "================================================"

echo -e "${BLUE}1.1: Deploying LOP on Sepolia...${NC}"
forge script script/DeployLimitOrderProtocol.s.sol:DeployLimitOrderProtocol \
    --rpc-url sepolia \
    --account deployerKey \
    --broadcast \
    --verify \
    -vv

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ LOP deployed successfully on Sepolia${NC}"
else
    echo -e "${RED}❌ LOP deployment failed on Sepolia${NC}"
    exit 1
fi

echo -e "${BLUE}1.2: Deploying LOP on Monad...${NC}"
forge script script/DeployLimitOrderProtocol.s.sol:DeployLimitOrderProtocol \
    --rpc-url monad_testnet \
    --account deployerKey \
    --broadcast \
    --verify \
    -vv

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ LOP deployed successfully on Monad${NC}"
else
    echo -e "${RED}❌ LOP deployment failed on Monad${NC}"
    exit 1
fi

echo ""

# =======================================================================
# Phase 2: Deploy Escrow Factories on both chains
# =======================================================================

echo -e "${YELLOW}Phase 2: Deploying Escrow Factories${NC}"
echo "==========================================="

echo -e "${BLUE}2.1: Deploying EscrowFactory on Sepolia...${NC}"
forge script script/DeployEscrowFactoryTestnet.s.sol:DeployEscrowFactoryTestnet \
    --rpc-url sepolia \
    --account deployerKey \
    --broadcast \
    --verify \
    -vv

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ EscrowFactory deployed successfully on Sepolia${NC}"
else
    echo -e "${RED}❌ EscrowFactory deployment failed on Sepolia${NC}"
    exit 1
fi

echo -e "${BLUE}2.2: Deploying EscrowFactory on Monad...${NC}"
forge script script/DeployEscrowFactoryMonad.s.sol:DeployEscrowFactoryMonad \
    --rpc-url monad_testnet \
    --account deployerKey \
    --broadcast \
    --verify \
    -vv

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ EscrowFactory deployed successfully on Monad${NC}"
else
    echo -e "${RED}❌ EscrowFactory deployment failed on Monad${NC}"
    exit 1
fi

echo ""

# =======================================================================
# Phase 3: Deploy Resolver contracts on both chains
# =======================================================================

echo -e "${YELLOW}Phase 3: Deploying Resolver Contracts${NC}"
echo "======================================"

echo -e "${BLUE}3.1: Deploying ResolverExample on Sepolia...${NC}"
forge script script/DeployResolver.s.sol:DeployResolver \
    --rpc-url sepolia \
    --account deployerKey \
    --broadcast \
    --verify \
    -vv

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ ResolverExample deployed successfully on Sepolia${NC}"
else
    echo -e "${RED}❌ ResolverExample deployment failed on Sepolia${NC}"
    exit 1
fi

echo -e "${BLUE}3.2: Deploying ResolverExample on Monad...${NC}"
forge script script/DeployResolver.s.sol:DeployResolver \
    --rpc-url monad_testnet \
    --account deployerKey \
    --broadcast \
    --verify \
    -vv

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ ResolverExample deployed successfully on Monad${NC}"
else
    echo -e "${RED}❌ ResolverExample deployment failed on Monad${NC}"
    exit 1
fi

echo ""

# =======================================================================
# Phase 4: Verify deployment and update configuration
# =======================================================================

echo -e "${YELLOW}Phase 4: Verifying Deployments${NC}"
echo "================================"

echo -e "${BLUE}4.1: Checking contract deployments...${NC}"

# Get new addresses from deployments.json
SEPOLIA_FACTORY=$(jq -r '.contracts.sepolia.escrowFactory' $DEPLOYMENTS_PATH)
SEPOLIA_RESOLVER=$(jq -r '.contracts.sepolia.resolver' $DEPLOYMENTS_PATH)
SEPOLIA_LOP=$(jq -r '.contracts.sepolia.limitOrderProtocol' $DEPLOYMENTS_PATH)

MONAD_FACTORY=$(jq -r '.contracts.monad.escrowFactory' $DEPLOYMENTS_PATH)
MONAD_RESOLVER=$(jq -r '.contracts.monad.resolver' $DEPLOYMENTS_PATH)
MONAD_LOP=$(jq -r '.contracts.monad.limitOrderProtocol' $DEPLOYMENTS_PATH)

echo ""
echo -e "${GREEN}📊 Deployment Summary:${NC}"
echo "========================="
echo ""
echo -e "${BLUE}Sepolia Contracts:${NC}"
echo "  EscrowFactory: $SEPOLIA_FACTORY"
echo "  ResolverExample: $SEPOLIA_RESOLVER"  
echo "  LimitOrderProtocol: $SEPOLIA_LOP"
echo ""
echo -e "${BLUE}Monad Contracts:${NC}"
echo "  EscrowFactory: $MONAD_FACTORY"
echo "  ResolverExample: $MONAD_RESOLVER"
echo "  LimitOrderProtocol: $MONAD_LOP"
echo ""
echo -e "${BLUE}Preserved Token Addresses:${NC}"
echo "  Sepolia - Access: $(jq -r '.contracts.sepolia.accessToken' $DEPLOYMENTS_PATH)"
echo "  Sepolia - Fee: $(jq -r '.contracts.sepolia.feeToken' $DEPLOYMENTS_PATH)"
echo "  Sepolia - Swap: $(jq -r '.contracts.sepolia.swapToken' $DEPLOYMENTS_PATH)"
echo "  Monad - Access: $(jq -r '.contracts.monad.accessToken' $DEPLOYMENTS_PATH)"
echo "  Monad - Fee: $(jq -r '.contracts.monad.feeToken' $DEPLOYMENTS_PATH)"
echo "  Monad - Swap: $(jq -r '.contracts.monad.swapToken' $DEPLOYMENTS_PATH)"
echo ""

# =======================================================================
# Phase 5: Final verification and cleanup
# =======================================================================

echo -e "${YELLOW}Phase 5: Final Verification${NC}"
echo "============================"

echo -e "${BLUE}5.1: Validating contract addresses...${NC}"

# Check that all addresses are valid (not null and not zero address)
if [[ "$SEPOLIA_FACTORY" != "null" && "$SEPOLIA_FACTORY" != "0x0000000000000000000000000000000000000000" ]] && \
   [[ "$SEPOLIA_RESOLVER" != "null" && "$SEPOLIA_RESOLVER" != "0x0000000000000000000000000000000000000000" ]] && \
   [[ "$SEPOLIA_LOP" != "null" && "$SEPOLIA_LOP" != "0x0000000000000000000000000000000000000000" ]] && \
   [[ "$MONAD_FACTORY" != "null" && "$MONAD_FACTORY" != "0x0000000000000000000000000000000000000000" ]] && \
   [[ "$MONAD_RESOLVER" != "null" && "$MONAD_RESOLVER" != "0x0000000000000000000000000000000000000000" ]] && \
   [[ "$MONAD_LOP" != "null" && "$MONAD_LOP" != "0x0000000000000000000000000000000000000000" ]]; then
    echo -e "${GREEN}✅ All contract addresses are valid${NC}"
else
    echo -e "${RED}❌ Some contract addresses are invalid${NC}"
    echo "Please check the deployment logs and deployments.json file"
    exit 1
fi

echo ""

# Final Success Message
echo "🎉 CONTRACT REDEPLOYMENT COMPLETE! 🎉"
echo "====================================="
echo -e "${GREEN}✅ All contracts successfully redeployed${NC}"
echo ""
echo "📋 What was deployed:"
echo "1. ✅ Limit Order Protocol on both chains"
echo "2. ✅ Escrow Factories on both chains"  
echo "3. ✅ Resolver contracts on both chains"
echo "4. ✅ All deployments verified on block explorers"
echo ""
echo "🔄 Next Steps:"
echo "- Use the new contract addresses from deployments.json"
echo "- Token addresses were preserved and remain unchanged"
echo "- You can now run atomic swaps with the updated contracts"
echo ""
echo "💾 Backup: Original deployments saved as ${DEPLOYMENTS_PATH}.backup.*"
echo ""
echo "🚀 Redeployment completed successfully!"