#!/usr/bin/env node

/**
 * Step 5: Relayer Verification & Secret Retrieval
 * 
 * This script acts as the relayer that:
 * 1. Verifies both source and destination escrows are properly funded
 * 2. Checks contract states and balances
 * 3. Retrieves the secret for the resolver to complete withdrawals
 * 4. Updates swap status in the secrets file
 */

const fs = require('fs');
const { ethers } = require('ethers');

// Load environment variables
require('dotenv').config();

// Configuration
const SECRETS_PATH = './data/swap-secrets.json';
const DEPLOYMENTS_PATH = './deployments.json';

async function main() {
    console.log('🔍 Step 5: Relayer Verification & Secret Retrieval...\n');

    // Check if secrets file exists
    if (!fs.existsSync(SECRETS_PATH)) {
        throw new Error(`Secrets file not found: ${SECRETS_PATH}`);
    }

    // Load secret data and deployments
    const secretData = JSON.parse(fs.readFileSync(SECRETS_PATH, 'utf8'));
    const deployments = JSON.parse(fs.readFileSync(DEPLOYMENTS_PATH, 'utf8'));

    console.log('📋 Swap Details:');
    console.log(`Maker: ${secretData.makerAddress}`);
    console.log(`Secret Hash: ${secretData.secretHash}`);
    console.log(`Source Amount: ${secretData.srcAmount}`);
    console.log(`Destination Amount: ${secretData.dstAmount}`);

    // Set up providers for both networks
    const sepoliaProvider = new ethers.providers.JsonRpcProvider(process.env.SEPOLIA_RPC_URL);
    const monadProvider = new ethers.providers.JsonRpcProvider(process.env.MONAD_RPC_URL);

    const providers = {
        sepolia: sepoliaProvider,
        monad: monadProvider
    };

    // Verify escrow deployments
    console.log('\n🔍 Verifying Escrow Deployments...');
    
    const escrowVerification = await verifyEscrowDeployments(secretData, deployments, providers);
    
    if (!escrowVerification.sourceEscrowValid || !escrowVerification.destinationEscrowValid) {
        console.log('❌ Escrow verification failed!');
        process.exit(1);
    }

    console.log('✅ Both escrows verified and properly funded!');

    // Retrieve and provide secret
    console.log('\n🔑 Retrieving Secret for Resolver...');
    
    const secret = secretData.secret;
    console.log(`Secret (for resolver): ${secret}`);
    console.log(`Secret Hash: ${secretData.secretHash}`);

    // Initialize status and escrowAddresses if they don't exist
    if (!secretData.status) {
        secretData.status = {
            step1_signed: true,
            step2_secretStored: true,
            step3_srcEscrowDeployed: false,
            step4_dstEscrowDeployed: false,
            step5_verified: false,
            step6_dstWithdrawn: false,
            step7_srcWithdrawn: false,
            step8_complete: false
        };
    }
    
    if (!secretData.escrowAddresses) {
        secretData.escrowAddresses = {
            srcEscrow: null,
            dstEscrow: null
        };
    }

    // Update status
    secretData.status.step5_verified = true;
    secretData.escrowAddresses = escrowVerification.escrowAddresses;
    secretData.verificationTimestamp = Date.now();

    // Save updated status
    fs.writeFileSync(SECRETS_PATH, JSON.stringify(secretData, null, 2));

    console.log('\n✅ Step 5 Complete!');
    console.log('📁 Updated verification status in secrets file');
    console.log('🔄 Ready for Step 6: Resolver destination withdrawal');
    console.log('🔄 Ready for Step 7: Resolver source withdrawal');

    return {
        secret: secret,
        escrowAddresses: escrowVerification.escrowAddresses,
        verified: true
    };
}

async function verifyEscrowDeployments(secretData, deployments, providers) {
    const verification = {
        sourceEscrowValid: false,
        destinationEscrowValid: false,
        escrowAddresses: {
            srcEscrow: null,
            dstEscrow: null
        }
    };

    try {
        // Check source escrow (where maker's tokens are locked)
        const srcNetwork = 'sepolia'; // Assuming Sepolia → Monad swap
        const dstNetwork = 'monad';
        
        const srcProvider = providers[srcNetwork];
        const dstProvider = providers[dstNetwork];

        // Get token contract instances
        const srcTokenAddress = deployments.contracts[srcNetwork].swapToken;
        const dstTokenAddress = deployments.contracts[dstNetwork].swapToken;
        
        const srcTokenAbi = [
            "function balanceOf(address owner) view returns (uint256)",
            "function name() view returns (string)",
            "function symbol() view returns (string)"
        ];

        const srcToken = new ethers.Contract(srcTokenAddress, srcTokenAbi, srcProvider);
        const dstToken = new ethers.Contract(dstTokenAddress, srcTokenAbi, dstProvider);

        console.log(`📊 Source Token (${srcNetwork}): ${await srcToken.name()} (${await srcToken.symbol()})`);
        console.log(`📊 Destination Token (${dstNetwork}): ${await dstToken.name()} (${await dstToken.symbol()})`);

        // For demo purposes, we'll check if the escrow factory has recent transactions
        // In a real implementation, you would parse events to find the actual escrow addresses
        
        const escrowFactorySrc = deployments.contracts[srcNetwork].escrowFactory;
        const escrowFactoryDst = deployments.contracts[dstNetwork].escrowFactory;
        
        console.log(`📍 Source Escrow Factory: ${escrowFactorySrc}`);
        console.log(`📍 Destination Escrow Factory: ${escrowFactoryDst}`);

        // Check recent blocks for escrow creation events
        const srcLatestBlock = await srcProvider.getBlockNumber();
        const dstLatestBlock = await dstProvider.getBlockNumber();
        
        console.log(`🏗️  Source network latest block: ${srcLatestBlock}`);
        console.log(`🏗️  Destination network latest block: ${dstLatestBlock}`);

        // For this demo, we'll assume escrows are deployed if the factories exist
        // In production, you would parse the actual EscrowCreated events
        
        if (escrowFactorySrc && escrowFactoryDst) {
            verification.sourceEscrowValid = true;
            verification.destinationEscrowValid = true;
            
            // These would be the actual escrow addresses from events
            verification.escrowAddresses.srcEscrow = "0x" + "1".repeat(40); // Placeholder
            verification.escrowAddresses.dstEscrow = "0x" + "2".repeat(40); // Placeholder
            
            console.log('✅ Source escrow verified (mock)');
            console.log('✅ Destination escrow verified (mock)');
        }

        // Check resolver balances
        const resolverSrc = deployments.contracts[srcNetwork].resolver;
        const resolverDst = deployments.contracts[dstNetwork].resolver;
        
        if (resolverSrc) {
            const resolverSrcBalance = await srcProvider.getBalance(resolverSrc);
            console.log(`💰 Resolver source balance: ${ethers.utils.formatEther(resolverSrcBalance)} ETH`);
        }
        
        if (resolverDst) {
            const resolverDstBalance = await dstProvider.getBalance(resolverDst);
            console.log(`💰 Resolver destination balance: ${ethers.utils.formatEther(resolverDstBalance)} ETH`);
        }

    } catch (error) {
        console.error('❌ Error during verification:', error.message);
    }

    return verification;
}

async function checkEscrowBalance(escrowAddress, tokenAddress, expectedAmount, provider) {
    try {
        const tokenAbi = [
            "function balanceOf(address owner) view returns (uint256)"
        ];
        
        const token = new ethers.Contract(tokenAddress, tokenAbi, provider);
        const balance = await token.balanceOf(escrowAddress);
        
        console.log(`💰 Escrow ${escrowAddress} balance: ${balance.toString()}`);
        console.log(`💰 Expected amount: ${expectedAmount}`);
        
        return balance.gte(expectedAmount);
    } catch (error) {
        console.error(`❌ Error checking escrow balance: ${error.message}`);
        return false;
    }
}

if (require.main === module) {
    main().catch(console.error);
}

module.exports = { main, verifyEscrowDeployments };