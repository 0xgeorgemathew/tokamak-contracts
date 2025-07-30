#!/bin/bash

set -e

echo "🔧 Setting up cast wallets for atomic swap demo..."

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}📋 Checking cast wallet configuration...${NC}"

# Check if wallets exist
if ! cast wallet list | grep -q "deployerKey"; then
    echo -e "${RED}❌ deployerKey wallet not found${NC}"
    echo "Please create wallets first:"
    echo "  cast wallet import deployerKey --interactive"
    echo "  cast wallet import bravoKey --interactive"
    exit 1
fi

if ! cast wallet list | grep -q "bravoKey"; then
    echo -e "${RED}❌ bravoKey wallet not found${NC}"
    echo "Please create wallets first:"
    echo "  cast wallet import deployerKey --interactive"
    echo "  cast wallet import bravoKey --interactive"
    exit 1
fi

echo -e "${GREEN}✅ Cast wallets found${NC}"

echo -e "${BLUE}🔐 Getting wallet addresses (encrypted wallets require password)...${NC}"
echo ""
echo -e "${YELLOW}Please run these commands and enter your wallet passwords:${NC}"
echo ""
echo "1. Get deployerKey address:"
echo "   cast wallet address deployerKey"
echo ""
echo "2. Get bravoKey address:"
echo "   cast wallet address bravoKey"
echo ""
echo "3. Set addresses in .env file:"
echo "   echo 'DEPLOYER_ADDRESS=<your_deployer_address>' >> .env"
echo "   echo 'MAKER_ADDRESS=<your_bravo_address>' >> .env"
echo ""

# Create .env file if it doesn't exist
if [ ! -f .env ]; then
    echo -e "${BLUE}📝 Creating .env file from template...${NC}"
    cp .env.example .env
    echo -e "${GREEN}✅ .env file created${NC}"
fi

# Check if addresses are already set
if [ -f .env ]; then
    source .env
    if [ -n "$DEPLOYER_ADDRESS" ] && [ "$DEPLOYER_ADDRESS" != "" ]; then
        echo -e "${GREEN}✅ DEPLOYER_ADDRESS already set: $DEPLOYER_ADDRESS${NC}"
    else
        echo -e "${YELLOW}⚠️  DEPLOYER_ADDRESS not set in .env${NC}"
    fi
    
    if [ -n "$MAKER_ADDRESS" ] && [ "$MAKER_ADDRESS" != "" ]; then
        echo -e "${GREEN}✅ MAKER_ADDRESS already set: $MAKER_ADDRESS${NC}"
    else
        echo -e "${YELLOW}⚠️  MAKER_ADDRESS not set in .env${NC}"
    fi
fi

# Check balances if addresses are set
if [ -n "$DEPLOYER_ADDRESS" ] && [ -n "$MAKER_ADDRESS" ] && [ "$DEPLOYER_ADDRESS" != "" ] && [ "$MAKER_ADDRESS" != "" ]; then
    echo -e "${BLUE}💰 Checking wallet balances...${NC}"

    # Check Sepolia balances
    echo "Sepolia Testnet:"
    DEPLOYER_BALANCE_SEPOLIA=$(cast balance $DEPLOYER_ADDRESS --rpc-url sepolia 2>/dev/null || echo "0")
    MAKER_BALANCE_SEPOLIA=$(cast balance $MAKER_ADDRESS --rpc-url sepolia 2>/dev/null || echo "0")

    echo "  deployerKey: $(cast from-wei $DEPLOYER_BALANCE_SEPOLIA) ETH"
    echo "  bravoKey:    $(cast from-wei $MAKER_BALANCE_SEPOLIA) ETH"

    # Check Monad balances
    echo "Monad Testnet:"
    DEPLOYER_BALANCE_MONAD=$(cast balance $DEPLOYER_ADDRESS --rpc-url monad_testnet 2>/dev/null || echo "0")
    MAKER_BALANCE_MONAD=$(cast balance $MAKER_ADDRESS --rpc-url monad_testnet 2>/dev/null || echo "0")

    echo "  deployerKey: $(cast from-wei $DEPLOYER_BALANCE_MONAD) ETH"
    echo "  bravoKey:    $(cast from-wei $MAKER_BALANCE_MONAD) ETH"

    # Check if wallets need funding (simplified check)
    if [ "$DEPLOYER_BALANCE_SEPOLIA" = "0" ] || [ "$DEPLOYER_BALANCE_MONAD" = "0" ]; then
        echo -e "${YELLOW}⚠️  deployerKey may need testnet ETH for gas${NC}"
        echo -e "${BLUE}💸 Funding Instructions:${NC}"
        echo "Get testnet ETH from faucets:"
        echo "  Sepolia: https://sepoliafaucet.com/"
        echo "  Monad:   https://faucet.monad.xyz/"
        echo ""
        echo "Send to deployerKey: $DEPLOYER_ADDRESS"
    fi
else
    echo -e "${YELLOW}⚠️  Cannot check balances - wallet addresses not set${NC}"
    echo "Please set DEPLOYER_ADDRESS and MAKER_ADDRESS in .env first"
fi

echo -e "${GREEN}✅ Wallet setup complete!${NC}"
echo -e "${BLUE}🚀 Next steps:${NC}"
echo "  1. Fund wallets if needed (see above)"
echo "  2. Run: make setup-testnet"
echo "  3. Run: make demo-swap-sepolia-to-monad"