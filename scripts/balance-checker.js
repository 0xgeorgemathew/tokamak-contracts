#!/usr/bin/env node

/**
 * Balance Checker: Real-time balance monitoring for hackathon demo
 * 
 * Displays token and native balances across both Sepolia and Monad networks
 * for the maker and deployer addresses involved in the atomic swap demo.
 */

const { ethers } = require('ethers');
const fs = require('fs');

// Load environment variables
require('dotenv').config();

// ERC20 ABI for balance checking
const ERC20_ABI = [
    "function balanceOf(address) external view returns (uint256)",
    "function symbol() external view returns (string)",
    "function decimals() external view returns (uint8)",
    "function name() external view returns (string)"
];

// Configuration
const DEPLOYMENTS_PATH = './deployments.json';

// Network configurations
const NETWORKS = {
    sepolia: {
        name: 'Ethereum Sepolia',
        chainId: 11155111,
        rpcUrl: process.env.SEPOLIA_RPC_URL || 'https://rpc.sepolia.org',
        nativeSymbol: 'SepoliaETH'
    },
    monad: {
        name: 'Monad Testnet',
        chainId: 10143,
        rpcUrl: process.env.MONAD_RPC_URL || 'https://testnet-rpc.monad.xyz',
        nativeSymbol: 'MON'
    }
};

// ANSI color codes
const colors = {
    reset: '\x1b[0m',
    bright: '\x1b[1m',
    red: '\x1b[31m',
    green: '\x1b[32m',
    yellow: '\x1b[33m',
    blue: '\x1b[34m',
    magenta: '\x1b[35m',
    cyan: '\x1b[36m',
    white: '\x1b[37m'
};

function colorize(text, color) {
    return `${colors[color]}${text}${colors.reset}`;
}

async function getTokenInfo(tokenAddress, provider) {
    try {
        const contract = new ethers.Contract(tokenAddress, ERC20_ABI, provider);
        const [symbol, decimals, name] = await Promise.all([
            contract.symbol(),
            contract.decimals(),
            contract.name()
        ]);
        return { symbol, decimals, name };
    } catch (error) {
        return { symbol: 'UNKNOWN', decimals: 18, name: 'Unknown Token' };
    }
}

async function getBalance(address, tokenAddress, provider, decimals = 18) {
    try {
        if (tokenAddress === ethers.constants.AddressZero || !tokenAddress) {
            // Native token balance
            const balance = await provider.getBalance(address);
            return ethers.utils.formatEther(balance);
        } else {
            // ERC20 token balance
            const contract = new ethers.Contract(tokenAddress, ERC20_ABI, provider);
            const balance = await contract.balanceOf(address);
            return ethers.utils.formatUnits(balance, decimals);
        }
    } catch (error) {
        return '0.00';
    }
}

async function displayNetworkBalances(networkKey, networkConfig, addresses, deployments) {
    console.log(colorize(`\n📊 ${networkConfig.name}`, 'cyan'));
    console.log(colorize('═'.repeat(50), 'cyan'));

    try {
        const provider = new ethers.providers.JsonRpcProvider(networkConfig.rpcUrl);
        
        // Check if provider is responsive
        await provider.getNetwork();
        
        const networkDeployment = deployments.contracts[networkKey];
        if (!networkDeployment) {
            console.log(colorize('   ⚠️  No deployment data available', 'yellow'));
            return;
        }

        // Get token info if available
        let tokenInfo = null;
        if (networkDeployment.swapToken) {
            tokenInfo = await getTokenInfo(networkDeployment.swapToken, provider);
        }

        // Display balances for each address
        for (const [role, address] of Object.entries(addresses)) {
            console.log(colorize(`\n👤 ${role}:`, 'blue'), colorize(address, 'white'));
            
            // Native token balance
            const nativeBalance = await getBalance(address, null, provider);
            const nativeFormatted = parseFloat(nativeBalance).toFixed(4);
            console.log(`   ${networkConfig.nativeSymbol}: ${colorize(nativeFormatted, 'green')}`);
            
            // Test token balance
            if (tokenInfo && networkDeployment.swapToken) {
                const tokenBalance = await getBalance(address, networkDeployment.swapToken, provider, tokenInfo.decimals);
                const tokenFormatted = parseFloat(tokenBalance).toFixed(2);
                console.log(`   ${tokenInfo.symbol}: ${colorize(tokenFormatted, 'green')}`);
            }
        }

        // Display contract addresses
        if (networkDeployment.escrowFactory || networkDeployment.resolver) {
            console.log(colorize('\n🏗️  Contracts:', 'magenta'));
            if (networkDeployment.escrowFactory) {
                console.log(`   Factory: ${colorize(networkDeployment.escrowFactory.slice(0, 10) + '...', 'white')}`);
            }
            if (networkDeployment.resolver) {
                console.log(`   Resolver: ${colorize(networkDeployment.resolver.slice(0, 10) + '...', 'white')}`);
            }
            if (tokenInfo && networkDeployment.swapToken) {
                console.log(`   ${tokenInfo.symbol} Token: ${colorize(networkDeployment.swapToken.slice(0, 10) + '...', 'white')}`);
            }
        }

    } catch (error) {
        console.log(colorize(`   ❌ Network unavailable: ${error.message}`, 'red'));
    }
}

async function main() {
    console.log(colorize('💰 Balance Checker: Real-time Demo Monitoring', 'bright'));
    console.log(colorize('═'.repeat(60), 'bright'));

    // Get addresses from environment
    const addresses = {
        'Deployer (Resolver)': process.env.DEPLOYER_ADDRESS,
        'Maker (User)': process.env.MAKER_ADDRESS
    };

    // Validate addresses
    for (const [role, address] of Object.entries(addresses)) {
        if (!address) {
            console.log(colorize(`❌ ${role} address not found in environment`, 'red'));
            return;
        }
    }

    // Load deployment data
    let deployments = {};
    if (fs.existsSync(DEPLOYMENTS_PATH)) {
        try {
            deployments = JSON.parse(fs.readFileSync(DEPLOYMENTS_PATH, 'utf8'));
        } catch (error) {
            console.log(colorize('⚠️  Could not load deployment data', 'yellow'));
        }
    } else {
        console.log(colorize('⚠️  No deployment file found', 'yellow'));
    }

    // Display timestamp
    const timestamp = new Date().toLocaleString();
    console.log(colorize(`\n🕐 Last updated: ${timestamp}`, 'yellow'));

    // Check balances on both networks
    for (const [networkKey, networkConfig] of Object.entries(NETWORKS)) {
        await displayNetworkBalances(networkKey, networkConfig, addresses, deployments);
    }

    // Display summary
    console.log(colorize('\n📈 Summary', 'cyan'));
    console.log(colorize('═'.repeat(20), 'cyan'));
    console.log('   • Balance monitoring active');
    console.log('   • Cross-chain balances displayed');
    console.log('   • Ready for atomic swap demonstration');

    console.log(colorize('\n🔄 Run this script continuously during demo to monitor changes', 'bright'));
}

// Watch mode for continuous monitoring
if (process.argv.includes('--watch')) {
    console.log(colorize('👀 Starting balance watch mode...', 'blue'));
    console.log(colorize('Press Ctrl+C to stop\n', 'yellow'));
    
    const runContinuously = async () => {
        await main();
        setTimeout(() => {
            console.clear();
            runContinuously();
        }, 10000); // Update every 10 seconds
    };
    
    runContinuously();
} else {
    // Single run
    if (require.main === module) {
        main().catch(error => {
            console.error(colorize(`Error: ${error.message}`, 'red'));
            process.exit(1);
        });
    }
}

module.exports = { main };