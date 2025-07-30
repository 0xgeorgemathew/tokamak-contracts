#!/usr/bin/env node

/**
 * Fund Resolver Script
 *
 * This script funds the resolver with source tokens so it can complete
 * the limit order when deploying the source escrow.
 */

const fs = require('fs');
const { ethers } = require('ethers');

// Load environment variables
require('dotenv').config();

// Configuration
const SECRETS_PATH = './data/swap-secrets.json';
const DEPLOYMENTS_PATH = './deployments.json';

// ERC20 ABI for transfer and mint functions
const ERC20_ABI = [
    "function transfer(address to, uint256 amount) external returns (bool)",
    "function balanceOf(address account) external view returns (uint256)",
    "function mint(address to, uint256 amount) external",
    "function decimals() external view returns (uint8)",
    "function symbol() external view returns (string)"
];

async function main() {
    console.log('💰 Funding Resolver with Source Tokens...\n');

    // Load configuration
    const secretData = JSON.parse(fs.readFileSync(SECRETS_PATH, 'utf8'));
    const deployments = JSON.parse(fs.readFileSync(DEPLOYMENTS_PATH, 'utf8'));

    const chainId = process.env.CHAIN_ID || '11155111'; // Default to Sepolia
    let rpcUrl, networkConfig;

    if (chainId === '11155111') {
        rpcUrl = process.env.SEPOLIA_RPC_URL || 'https://rpc.sepolia.org';
        networkConfig = deployments.contracts.sepolia;
    } else if (chainId === '10143') {
        rpcUrl = process.env.MONAD_RPC_URL || 'https://testnet-rpc.monad.xyz';
        networkConfig = deployments.contracts.monad;
    } else {
        throw new Error(`Unsupported chain ID: ${chainId}`);
    }

    console.log(`Network: ${chainId === '11155111' ? 'sepolia' : 'monad'}`);
    console.log(`Source Token: ${secretData.srcToken}`);
    console.log(`Resolver: ${networkConfig.resolver}`);
    console.log(`Amount Needed: ${secretData.srcAmount}`);

    // Set up provider and wallet
    const provider = new ethers.providers.JsonRpcProvider(rpcUrl);
    const deployerPrivateKey = process.env.DEPLOYER_PRIVATE_KEY;
    if (!deployerPrivateKey) {
        throw new Error('DEPLOYER_PRIVATE_KEY not set in .env');
    }
    const wallet = new ethers.Wallet(deployerPrivateKey, provider);

    // Create token contract instance
    const tokenContract = new ethers.Contract(secretData.srcToken, ERC20_ABI, wallet);

    try {
        // Get token info
        const [resolverBalance, decimals, symbol] = await Promise.all([
            tokenContract.balanceOf(networkConfig.resolver),
            tokenContract.decimals(),
            tokenContract.symbol()
        ]);

        console.log(`\n📊 Current State:`);
        console.log(`Token Symbol: ${symbol}`);
        console.log(`Resolver Balance: ${ethers.utils.formatUnits(resolverBalance, decimals)} ${symbol}`);
        console.log(`Required Amount: ${ethers.utils.formatUnits(secretData.srcAmount, decimals)} ${symbol}`);

        // Check if resolver already has enough tokens
        if (resolverBalance.gte(secretData.srcAmount)) {
            console.log(`\n✅ Resolver already has sufficient tokens!`);
            console.log(`Balance (${ethers.utils.formatUnits(resolverBalance, decimals)} ${symbol}) >= required (${ethers.utils.formatUnits(secretData.srcAmount, decimals)} ${symbol})`);
            return;
        }

        // Calculate amount to mint/transfer
        const amountNeeded = ethers.BigNumber.from(secretData.srcAmount).sub(resolverBalance);
        console.log(`\n💰 Need to provide ${ethers.utils.formatUnits(amountNeeded, decimals)} ${symbol} to resolver`);

        // Check if we're on a testnet where we can mint
        if (chainId === '31337') {
            // Local testnet - mint tokens directly
            console.log('🔨 Minting tokens to resolver (local testnet)...');
            const mintTx = await tokenContract.mint(networkConfig.resolver, amountNeeded);
            console.log(`📝 Mint transaction sent: ${mintTx.hash}`);
            await mintTx.wait();
            console.log(`✅ Minted ${ethers.utils.formatUnits(amountNeeded, decimals)} ${symbol} to resolver`);
        } else {
            // Real testnet - transfer from deployer
            const deployerBalance = await tokenContract.balanceOf(wallet.address);
            console.log(`Deployer Balance: ${ethers.utils.formatUnits(deployerBalance, decimals)} ${symbol}`);

            if (deployerBalance.lt(amountNeeded)) {
                throw new Error(`Insufficient deployer balance: ${ethers.utils.formatUnits(deployerBalance, decimals)} < ${ethers.utils.formatUnits(amountNeeded, decimals)}`);
            }

            console.log('📤 Transferring tokens from deployer to resolver...');
            const transferTx = await tokenContract.transfer(networkConfig.resolver, amountNeeded);
            console.log(`📝 Transfer transaction sent: ${transferTx.hash}`);
            await transferTx.wait();
            console.log(`✅ Transferred ${ethers.utils.formatUnits(amountNeeded, decimals)} ${symbol} to resolver`);
        }

        // Verify final balance
        const newResolverBalance = await tokenContract.balanceOf(networkConfig.resolver);
        console.log(`\n🔍 Final resolver balance: ${ethers.utils.formatUnits(newResolverBalance, decimals)} ${symbol}`);

        if (newResolverBalance.gte(secretData.srcAmount)) {
            console.log(`✅ Resolver funding successful!`);
        } else {
            throw new Error('Resolver funding verification failed');
        }

    } catch (error) {
        console.error(`❌ Error funding resolver: ${error.message}`);
        throw error;
    }
}

if (require.main === module) {
    main().catch(console.error);
}

module.exports = { main };