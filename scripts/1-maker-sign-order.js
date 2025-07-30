#!/usr/bin/env node

/**
 * Step 1: Maker Off-Chain Signature Creation
 *
 * This script allows the maker (token holder) to create an EIP-712 signature
 * that approves token transfer for the atomic swap. The signature will be used
 * by the resolver in Step 3 to deploy the source escrow.
 */

const fs = require('fs');
const path = require('path');
// Import BigNumber along with ethers
const { ethers, BigNumber } = require('ethers');

// Load environment variables
require('dotenv').config();

// ERC20 ABI for decimals function
const ERC20_ABI = [
    "function decimals() external view returns (uint8)"
];

// Configuration
const CONFIG_PATH = process.env.CONFIG_PATH || './examples/config/config.json';
const DEPLOYMENTS_PATH = './deployments.json';
const SECRETS_PATH = './data/swap-secrets.json';

async function main() {
    console.log('🔐 Step 1: Creating Maker Off-Chain Signature...\n');

    // Load configuration
    const config = JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8'));
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
    console.log(`Maker in config: ${config.maker}`);

    // Verify maker address matches
    if (makerAddress.toLowerCase() !== config.maker.toLowerCase()) {
        throw new Error(`Maker address mismatch: ${makerAddress} !== ${config.maker}`);
    }

    // Get current chain tokens based on network
    const chainId = process.env.CHAIN_ID || '11155111'; // Default to Sepolia
    const networkConfig = chainId === '11155111' ? deployments.contracts.sepolia : deployments.contracts.monad;

    // Load secret data if exists, otherwise create new
    let secretData;
    if (fs.existsSync(SECRETS_PATH)) {
        secretData = JSON.parse(fs.readFileSync(SECRETS_PATH, 'utf8'));
        console.log('📖 Loaded existing secret data');
    } else {
        // Create new secret
        const secret = ethers.utils.formatBytes32String(config.secret || 'secret1');
        const secretHash = ethers.utils.keccak256(ethers.utils.keccak256(secret));

        secretData = {
            secret: secret,
            secretHash: secretHash,
            timestamp: Date.now(),
            makerAddress: makerAddress,
            srcToken: networkConfig.swapToken,
            dstToken: chainId === '11155111' ? deployments.contracts.monad.swapToken : deployments.contracts.sepolia.swapToken,
            srcAmount: config.srcAmount,
            dstAmount: config.dstAmount,
            resolverAddress: config.resolver,
            safetyDeposit: config.safetyDeposit
        };

        console.log('🆕 Created new secret data');
    }

    // Create EIP-712 domain for Limit Order Protocol
    const domain = {
        name: "1inch Limit Order Protocol",
        version: "4",
        chainId: parseInt(chainId),
        verifyingContract: networkConfig.limitOrderProtocol
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

    // Generate salt that avoids invalidated bit positions in BitInvalidator
    // Bit position is determined by salt % 256, and bit 0 is invalidated
    let saltValue;
    do {
        // Use a more unique approach: current timestamp + process id + random
        saltValue = Date.now() * 1000 + process.pid + Math.floor(Math.random() * 1000000); 
    } while (saltValue % 256 === 0); // Avoid mapping to invalidated bit position 0
    
    const deterministicSalt = ethers.utils.hexZeroPad(ethers.utils.hexlify(saltValue), 32);

    // No flags needed since no extension
    const makerTraits = "0";

    // Get token decimals for proper amount conversion
    let rpcUrl;
    if (chainId === '11155111') {
        rpcUrl = process.env.SEPOLIA_RPC_URL || 'https://rpc.sepolia.org';
    } else if (chainId === '10143') {
        rpcUrl = process.env.MONAD_RPC_URL || 'https://testnet-rpc.monad.xyz';
    } else {
        throw new Error(`Unsupported chain ID: ${chainId}`);
    }

    const provider = new ethers.providers.JsonRpcProvider(rpcUrl);
    const tokenContract = new ethers.Contract(secretData.srcToken, ERC20_ABI, provider);
    const decimals = await tokenContract.decimals();
    
    console.log(`\n📊 Token Information:`);
    console.log(`Token Address: ${secretData.srcToken}`);
    console.log(`Token Decimals: ${decimals}`);
    console.log(`Raw Amount: ${secretData.srcAmount}`);
    
    // Convert amounts to wei using token decimals
    const makingAmountWei = ethers.utils.parseUnits(secretData.srcAmount.toString(), decimals);
    // For atomic swaps, takingAmount should match makingAmount to ensure proper token transfer
    // The LOP will transfer takingAmount to the escrow, and factory validates against makingAmount
    const takingAmountWei = makingAmountWei;
    
    console.log(`Wei Amount: ${makingAmountWei.toString()}`);
    console.log(`Formatted: ${ethers.utils.formatUnits(makingAmountWei, decimals)} tokens`);

    // Create order data for cross-chain atomic swap
    // Both makingAmount and takingAmount must match so LOP transfers correct amount to escrow
    // The factory validates escrow has at least makingAmount tokens
    const order = {
        salt: deterministicSalt,
        maker: makerAddress,
        receiver: ethers.constants.AddressZero,
        makerAsset: secretData.srcToken,
        takerAsset: secretData.srcToken, // Same token required by LOP
        makingAmount: makingAmountWei.toString(),
        takingAmount: takingAmountWei.toString(), // Must match makingAmount for proper escrow funding
        makerTraits: makerTraits
    };

    console.log('\n📋 Order Details:');
    console.log(`Salt: ${order.salt}`);
    console.log(`Maker: ${order.maker}`);
    console.log(`Receiver: ${order.receiver}`);
    console.log(`Maker Asset: ${order.makerAsset}`);
    console.log(`Taker Asset: ${order.takerAsset}`);
    console.log(`Making Amount: ${order.makingAmount}`);
    console.log(`Taking Amount: ${order.takingAmount}`);
    console.log(`Maker Traits: ${order.makerTraits}`);

    // Sign the order
    console.log('\n✍️  Signing order...');
    const signature = await wallet._signTypedData(domain, types, order);
    const { v, r, s } = ethers.utils.splitSignature(signature);

    // FIX: Create vs format for 1inch protocol using BigNumber for safety
    // This prevents the JavaScript number overflow
    const vs = BigNumber.from(v - 27) // 0 or 1
        .shl(255) // shift left to the highest bit
        .or(BigNumber.from(s)) // combine with s
        .toHexString();

    const signatureData = {
        signature: signature,
        r: r,
        s: s,
        v: v,
        vs: vs, // Use the correctly calculated hex string
        order: order,
        domain: domain,
        types: types
    };

    // Update secret data with signature
    secretData.signatureData = signatureData;
    secretData.orderHash = ethers.utils._TypedDataEncoder.hash(domain, types, order);

    // Ensure data directory exists
    const dataDir = path.dirname(SECRETS_PATH);
    if (!fs.existsSync(dataDir)) {
        fs.mkdirSync(dataDir, { recursive: true });
    }

    // Save updated secret data
    fs.writeFileSync(SECRETS_PATH, JSON.stringify(secretData, null, 2));

    // Validate salt doesn't map to invalidated bit positions
    const bitPosition = saltValue % 256;
    console.log(`\n🔍 BitInvalidator Analysis:`);
    console.log(`Salt value: ${saltValue}`);
    console.log(`Maps to bit position: ${bitPosition} (safe - not 0)`);
    
    console.log('\n✅ Step 1 Complete!');
    console.log(`📁 Signature data saved to: ${SECRETS_PATH}`);
    console.log(`🔑 Order Hash: ${secretData.orderHash}`);
    console.log(`📝 Signature: ${signature}`);
    console.log(`🧂 Salt Used: ${deterministicSalt}`);
    console.log(`🔢 Salt Value: ${saltValue}`);
    console.log('\n🔄 Ready for Step 2: Secret storage (already completed)');
    console.log('🔄 Ready for Step 3: Resolver source escrow deployment');

    return secretData;
}

if (require.main === module) {
    main().catch(console.error);
}

module.exports = { main };
