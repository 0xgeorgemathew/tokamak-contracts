#!/usr/bin/env node

/**
 * Demo Order Signing: Simplified order signing for hackathon demonstration
 * 
 * This script creates EIP-712 signatures for atomic swap orders with
 * simplified configuration and error handling for demo purposes.
 */

const fs = require('fs');
const path = require('path');
const { ethers, BigNumber } = require('ethers');

// Load environment variables
require('dotenv').config();

// ERC20 ABI for decimals function
const ERC20_ABI = [
    "function decimals() external view returns (uint8)",
    "function symbol() external view returns (string)",
    "function name() external view returns (string)"
];

// Configuration
const DEPLOYMENTS_PATH = './deployments.json';
const SECRETS_BASE_PATH = './data';

async function main() {
    console.log('🔐 Demo Order Signing: Creating Maker Signature...\n');

    // Get parameters from environment
    const chainId = process.env.CHAIN_ID || '11155111'; // Default to Sepolia
    const direction = process.env.DIRECTION || 'sepolia-to-monad';
    
    console.log(`Chain ID: ${chainId}`);
    console.log(`Direction: ${direction}`);

    // Load deployment configuration
    if (!fs.existsSync(DEPLOYMENTS_PATH)) {
        throw new Error(`Deployments file not found: ${DEPLOYMENTS_PATH}`);
    }

    const deployments = JSON.parse(fs.readFileSync(DEPLOYMENTS_PATH, 'utf8'));
    
    // Get maker private key for signing
    const makerPrivateKey = process.env.MAKER_PRIVATE_KEY_FOR_SIGNING;
    if (!makerPrivateKey) {
        throw new Error('MAKER_PRIVATE_KEY_FOR_SIGNING not set in .env');
    }

    // Create wallet for signing
    const wallet = new ethers.Wallet(makerPrivateKey);
    const makerAddress = wallet.address;

    console.log(`Maker Address: ${makerAddress}`);

    // Determine source and destination networks
    let sourceNetwork, destNetwork, sourceConfig, destConfig;
    
    if (chainId === '11155111' || direction === 'sepolia-to-monad') {
        sourceNetwork = 'sepolia';
        destNetwork = 'monad';
        sourceConfig = deployments.contracts.sepolia;
        destConfig = deployments.contracts.monad;
    } else {
        sourceNetwork = 'monad';
        destNetwork = 'sepolia';
        sourceConfig = deployments.contracts.monad;
        destConfig = deployments.contracts.sepolia;
    }

    console.log(`Source: ${sourceNetwork} (Chain ${sourceConfig.chainId})`);
    console.log(`Destination: ${destNetwork} (Chain ${destConfig.chainId})`);

    // Get RPC URL for source chain
    let rpcUrl;
    if (sourceNetwork === 'sepolia') {
        rpcUrl = process.env.SEPOLIA_RPC_URL || 'https://rpc.sepolia.org';
    } else {
        rpcUrl = process.env.MONAD_RPC_URL || 'https://testnet-rpc.monad.xyz';
    }

    // Connect to provider and get token info
    const provider = new ethers.providers.JsonRpcProvider(rpcUrl);
    const tokenContract = new ethers.Contract(sourceConfig.swapToken, ERC20_ABI, provider);
    
    let decimals, symbol, tokenName;
    try {
        decimals = await tokenContract.decimals();
        symbol = await tokenContract.symbol();
        tokenName = await tokenContract.name();
    } catch (error) {
        console.log('Warning: Could not fetch token details, using defaults');
        decimals = 18;
        symbol = 'TEST';
        tokenName = 'Test Token';
    }

    console.log(`\n📊 Token Information:`);
    console.log(`Token: ${tokenName} (${symbol})`);
    console.log(`Address: ${sourceConfig.swapToken}`);
    console.log(`Decimals: ${decimals}`);

    // Demo configuration - simplified amounts
    const demoConfig = {
        swapAmount: '100', // 100 tokens
        safetyDeposit: ethers.utils.parseEther('0.01').toString(), // 0.01 ETH
        secret: `demo_secret_${Date.now()}_${Math.floor(Math.random() * 1000)}`
    };

    // Create unique secret and hash
    const secret = ethers.utils.formatBytes32String(demoConfig.secret);
    const secretHash = ethers.utils.keccak256(ethers.utils.keccak256(secret));

    console.log(`\n🔑 Secret Information:`);
    console.log(`Secret: "${demoConfig.secret}"`);
    console.log(`Hash: ${secretHash}`);

    // Convert amounts to wei
    const swapAmountWei = ethers.utils.parseUnits(demoConfig.swapAmount, decimals);
    
    console.log(`\n💰 Swap Details:`);
    console.log(`Amount: ${demoConfig.swapAmount} ${symbol}`);
    console.log(`Wei: ${swapAmountWei.toString()}`);

    // Create EIP-712 domain for Limit Order Protocol
    const domain = {
        name: "1inch Limit Order Protocol",
        version: "4",
        chainId: parseInt(sourceConfig.chainId),
        verifyingContract: sourceConfig.limitOrderProtocol
    };

    // Define Order type for EIP-712
    const types = {
        Order: [
            { name: "salt", type: "uint256" },
            { name: "maker", type: "address" },
            { name: "receiver", type: "address" },
            { name: "makerAsset", type: "address" },
            { name: "takerAsset", type: "address" },
            { name: "makingAmount", type: "uint256" },
            { name: "takingAmount", type: "uint256" },
            { name: "makerTraits", type: "uint256" },
        ]
    };

    // Generate unique salt
    const saltValue = Date.now() * 1000 + process.pid + Math.floor(Math.random() * 1000000);
    const salt = ethers.utils.hexZeroPad(ethers.utils.hexlify(saltValue), 32);

    // Create order for atomic swap
    const order = {
        salt: salt,
        maker: makerAddress,
        receiver: ethers.constants.AddressZero,
        makerAsset: sourceConfig.swapToken,
        takerAsset: sourceConfig.swapToken, // Same token for LOP compatibility
        makingAmount: swapAmountWei.toString(),
        takingAmount: swapAmountWei.toString(), // Match making amount
        makerTraits: "0" // No special traits needed
    };

    console.log('\n📋 Order Details:');
    console.log(`Salt: ${order.salt}`);
    console.log(`Maker: ${order.maker}`);
    console.log(`Asset: ${order.makerAsset}`);
    console.log(`Amount: ${order.makingAmount}`);

    // Sign the order
    console.log('\n✍️ Signing order...');
    const signature = await wallet._signTypedData(domain, types, order);
    const { v, r, s } = ethers.utils.splitSignature(signature);

    // Create vs format for 1inch protocol
    const vs = BigNumber.from(v - 27)
        .shl(255)
        .or(BigNumber.from(s))
        .toHexString();

    // Create comprehensive swap data
    const swapData = {
        // Metadata
        timestamp: Date.now(),
        direction: direction,
        sourceNetwork: sourceNetwork,
        destinationNetwork: destNetwork,
        
        // Secret data
        secret: secret,
        secretHash: secretHash,
        secretString: demoConfig.secret,
        
        // Addresses
        makerAddress: makerAddress,
        resolverAddress: sourceConfig.resolver,
        sourceToken: sourceConfig.swapToken,
        destinationToken: destConfig.swapToken,
        
        // Amounts
        swapAmount: demoConfig.swapAmount,
        swapAmountWei: swapAmountWei.toString(),
        safetyDeposit: demoConfig.safetyDeposit,
        
        // Token info
        tokenInfo: {
            symbol: symbol,
            name: tokenName,
            decimals: decimals
        },
        
        // Order and signature
        order: order,
        orderHash: ethers.utils._TypedDataEncoder.hash(domain, types, order),
        signature: {
            full: signature,
            r: r,
            s: s,
            v: v,
            vs: vs
        },
        
        // EIP-712 domain
        domain: domain,
        types: types,
        
        // Network configurations
        networks: {
            source: sourceConfig,
            destination: destConfig
        },
        
        // Status tracking
        status: {
            signed: true,
            sourceEscrowDeployed: false,
            destinationEscrowDeployed: false,
            secretRevealed: false,
            completed: false
        }
    };

    // Ensure data directory exists
    if (!fs.existsSync(SECRETS_BASE_PATH)) {
        fs.mkdirSync(SECRETS_BASE_PATH, { recursive: true });
    }

    // Save swap data with descriptive filename
    const filename = `demo-swap-${direction}-${Date.now()}.json`;
    const filepath = path.join(SECRETS_BASE_PATH, filename);
    
    fs.writeFileSync(filepath, JSON.stringify(swapData, null, 2));

    // Also create/update the standard secrets file for compatibility
    const standardSecretsPath = path.join(SECRETS_BASE_PATH, 'swap-secrets.json');
    fs.writeFileSync(standardSecretsPath, JSON.stringify({
        secret: secret,
        secretHash: secretHash,
        signatureData: {
            r: r,
            vs: vs,
            order: order
        },
        ...swapData
    }, null, 2));

    console.log('\n✅ Demo Order Signing Complete!');
    console.log(`📁 Swap data saved to: ${filepath}`);
    console.log(`📁 Standard format: ${standardSecretsPath}`);
    console.log(`🔑 Order Hash: ${swapData.orderHash}`);
    console.log(`📝 Direction: ${direction}`);
    console.log(`💱 ${swapData.swapAmount} ${symbol} (${sourceNetwork} → ${destNetwork})`);
    console.log('\n🔄 Ready for escrow deployment!');

    return swapData;
}

if (require.main === module) {
    main().catch(error => {
        console.error('Error:', error.message);
        process.exit(1);  
    });
}

module.exports = { main };