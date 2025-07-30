#!/usr/bin/env node

/**
 * Step 2: Maker Token Approval
 *
 * This script allows the maker to approve the Limit Order Protocol to spend
 * their source tokens for the atomic swap. This must be done after Step 1
 * (off-chain signature) and before Step 3 (escrow deployment).
 */

const fs = require('fs');
const { ethers } = require('ethers');

// Load environment variables
require('dotenv').config();

// Configuration
const SECRETS_PATH = './data/swap-secrets.json';
const DEPLOYMENTS_PATH = './deployments.json';

// ERC20 ABI for approve function
const ERC20_ABI = [
    "function approve(address spender, uint256 amount) external returns (bool)",
    "function allowance(address owner, address spender) external view returns (uint256)",
    "function balanceOf(address account) external view returns (uint256)",
    "function decimals() external view returns (uint8)",
    "function symbol() external view returns (string)"
];

async function main() {
    console.log('💰 Step 2: Maker Token Approval...\n');

    // Check if secrets file exists (should be created in Step 1)
    if (!fs.existsSync(SECRETS_PATH)) {
        throw new Error(`Secrets file not found: ${SECRETS_PATH}. Please run Step 1 first.`);
    }

    // Load secret data from Step 1
    const secretData = JSON.parse(fs.readFileSync(SECRETS_PATH, 'utf8'));
    const deployments = JSON.parse(fs.readFileSync(DEPLOYMENTS_PATH, 'utf8'));

    console.log(`Maker Address: ${secretData.makerAddress}`);
    console.log(`Source Token: ${secretData.srcToken}`);
    console.log(`Amount to Approve: ${secretData.srcAmount}`);

    // Get maker private key for transaction
    const makerPrivateKey = process.env.MAKER_PRIVATE_KEY_FOR_SIGNING;
    if (!makerPrivateKey) {
        throw new Error('MAKER_PRIVATE_KEY_FOR_SIGNING not set in .env');
    }

    // Determine which network we're on based on source token
    const chainId = process.env.CHAIN_ID || '11155111'; // Default to Sepolia
    let rpcUrl, networkName, limitOrderProtocol;

    if (chainId === '11155111') {
        rpcUrl = process.env.SEPOLIA_RPC_URL || 'https://rpc.sepolia.org';
        networkName = 'sepolia';
        limitOrderProtocol = deployments.contracts.sepolia.limitOrderProtocol;
    } else if (chainId === '10143') {
        rpcUrl = process.env.MONAD_RPC_URL || 'https://testnet-rpc.monad.xyz';
        networkName = 'monad';
        limitOrderProtocol = deployments.contracts.monad.limitOrderProtocol;
    } else {
        throw new Error(`Unsupported chain ID: ${chainId}`);
    }

    console.log(`Network: ${networkName}`);
    console.log(`Limit Order Protocol: ${limitOrderProtocol}`);

    // Set up provider and wallet
    const provider = new ethers.providers.JsonRpcProvider(rpcUrl);
    const wallet = new ethers.Wallet(makerPrivateKey, provider);

    // Verify maker address matches
    if (wallet.address.toLowerCase() !== secretData.makerAddress.toLowerCase()) {
        throw new Error(`Maker address mismatch: ${wallet.address} !== ${secretData.makerAddress}`);
    }

    // Create token contract instance
    const tokenContract = new ethers.Contract(secretData.srcToken, ERC20_ABI, wallet);

    try {
        // Get token info
        const [balance, currentAllowance, decimals, symbol] = await Promise.all([
            tokenContract.balanceOf(wallet.address),
            tokenContract.allowance(wallet.address, limitOrderProtocol),
            tokenContract.decimals(),
            tokenContract.symbol()
        ]);

        // **FIX: Convert the human-readable amount to the token's smallest unit**
        const amountToApprove = ethers.utils.parseUnits(secretData.srcAmount.toString(), decimals);

        console.log(`\n📊 Token Information:`);
        console.log(`Symbol: ${symbol}`);
        console.log(`Decimals: ${decimals}`);
        console.log(`Maker Balance: ${ethers.utils.formatUnits(balance, decimals)} ${symbol}`);
        console.log(`Current Allowance: ${ethers.utils.formatUnits(currentAllowance, decimals)} ${symbol}`);
        console.log(`Required Amount: ${ethers.utils.formatUnits(amountToApprove, decimals)} ${symbol}`);

        // Check if maker has sufficient balance
        if (balance.lt(amountToApprove)) {
            throw new Error(`Insufficient balance: ${ethers.utils.formatUnits(balance, decimals)} < ${ethers.utils.formatUnits(amountToApprove, decimals)}`);
        }

        // Check if approval is already sufficient
        if (currentAllowance.gte(amountToApprove)) {
            console.log(`\n✅ Sufficient approval already exists!`);
            console.log(`Current allowance (${ethers.utils.formatUnits(currentAllowance, decimals)} ${symbol}) >= required amount (${ethers.utils.formatUnits(amountToApprove, decimals)} ${symbol})`);

            // Update secret data to mark approval as complete
            secretData.approvalComplete = true;
            secretData.approvalTimestamp = Date.now();
            fs.writeFileSync(SECRETS_PATH, JSON.stringify(secretData, null, 2));

            console.log('\n🔄 Ready for Step 3: Resolver source escrow deployment');
            return secretData;
        }

        // Approve tokens
        console.log(`\n💰 Approving ${ethers.utils.formatUnits(amountToApprove, decimals)} ${symbol} for Limit Order Protocol...`);

        const approveTx = await tokenContract.approve(limitOrderProtocol, amountToApprove);
        console.log(`📝 Approval transaction sent: ${approveTx.hash}`);

        console.log('⏳ Waiting for confirmation...');
        const receipt = await approveTx.wait();

        if (receipt.status === 1) {
            console.log(`✅ Approval confirmed in block ${receipt.blockNumber}`);

            // Verify the approval
            const newAllowance = await tokenContract.allowance(wallet.address, limitOrderProtocol);
            console.log(`🔍 Verified allowance: ${ethers.utils.formatUnits(newAllowance, decimals)} ${symbol}`);

            if (newAllowance.gte(amountToApprove)) {
                console.log(`✅ Approval successful!`);

                // Update secret data
                secretData.approvalComplete = true;
                secretData.approvalTimestamp = Date.now();
                secretData.approvalTxHash = approveTx.hash;
                secretData.approvalBlockNumber = receipt.blockNumber;
                fs.writeFileSync(SECRETS_PATH, JSON.stringify(secretData, null, 2));

                console.log('\n✅ Step 2 Complete!');
                console.log(`📁 Approval data saved to: ${SECRETS_PATH}`);
                console.log('🔄 Ready for Step 3: Resolver source escrow deployment');
            } else {
                throw new Error('Approval verification failed');
            }
        } else {
            throw new Error('Approval transaction failed');
        }

    } catch (error) {
        console.error(`❌ Error during token approval: ${error.message}`);
        throw error;
    }

    return secretData;
}

if (require.main === module) {
    main().catch(console.error);
}

module.exports = { main };
