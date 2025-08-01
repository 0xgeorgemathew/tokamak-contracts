#!/bin/zsh

set -e # exit on error

# Source the .env file to load the variables
if [ -f .env ]; then
    source .env
else
    echo "Error: .env file not found"
    exit 1
fi

# Define the chain configurations
typeset -A chains
chains["mainnet"]="$MAINNET_RPC_URL"
chains["sepolia"]="$SEPOLIA_RPC_URL"
chains["goerli"]="$GOERLI_RPC_URL"
chains["bsc"]="$BSC_RPC_URL"
chains["polygon"]="$POLYGON_RPC_URL"
chains["avalanche"]="$AVALANCHE_RPC_URL"
chains["gnosis"]="$GNOSIS_RPC_URL"
chains["arbitrum"]="$ARBITRUM_RPC_URL"
chains["optimism"]="$OPTIMISM_RPC_URL"
chains["base"]="$BASE_RPC_URL"
chains["zksync"]="$ZKSYNC_RPC_URL"
chains["linea"]="$LINEA_RPC_URL"
chains["sonic"]="$SONIC_RPC_URL"
chains["unichain"]="$UNICHAIN_RPC_URL"
chains["monad"]="$MONAD_RPC_URL"

rpc_url="${chains["$1"]}"
if [ -z "$rpc_url" ]; then
    echo "Chain not found"
    exit 1
fi
echo "Provided chain: $1"
echo "RPC URL: $rpc_url"

keystore="$HOME/.foundry/keystores/$2"
echo "Keystore: $keystore"
if [ -e "$keystore" ]; then
    echo "Keystore provided"
else
    echo "Keystore not provided"
    exit 1
fi

if [ "$1" = "zksync" ]; then
    forge script script/DeployEscrowFactoryZkSync.s.sol --zksync --fork-url $rpc_url --keystore $keystore --broadcast -vvvv
elif [ "$1" = "monad" ]; then
    forge script script/DeployEscrowFactoryMonad.s.sol \
        --rpc-url $rpc_url \
        --keystore $keystore \
        --broadcast \
        --verify \
        --verifier sourcify \
        --verifier-url 'https://sourcify-api-monad.blockvision.org' \
        -vvvv
elif [ "$1" = "sepolia" ] || [ "$1" = "goerli" ]; then
    forge script script/DeployEscrowFactoryTestnet.s.sol \
        --rpc-url $rpc_url \
        --keystore $keystore \
        --broadcast \
        --verify \
        --etherscan-api-key $ETHERSCAN_API_KEY \
        -vvvv
else
    forge script script/DeployEscrowFactory.s.sol --fork-url $rpc_url --keystore $keystore --broadcast -vvvv
fi
