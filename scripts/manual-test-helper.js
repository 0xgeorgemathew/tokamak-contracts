#!/usr/bin/env node

const crypto = require("crypto");

// Fresh values
const SECRET =
    "0x70cb94131e655c51bbb4e33fda0286630976510deab5158b880f231dfacc105b";
const HASHLOCK =
    "0x8bc8f3483f31b6b02850757a0440020d36f250a93d39ece0a584f45ad13e8422";
const DEPLOYER = "0x20E5B952942417D4CB99d64a9e06e41Dcef00000";

// Contract addresses
const MONAD = {
    escrowFactory: "0x756B01844D85010C549cEf98daBdBC73e6372804",
    feeToken: "0xB7D3E26b95ffA0D02D9639329b56e75766cf5ba6",
};

const SEPOLIA = {
    escrowFactory: "0x4cD98318Ff73600B052849dd7735fC859D588582",
    testUSDC: "0xD3533927EbA467b98c62360451B3f98a6B89d750",
};

// Generate test parameters
const orderHash = "0x" + crypto.randomBytes(32).toString("hex");
const currentTime = Math.floor(Date.now() / 1000);

console.log("=== FRESH MANUAL CROSS-CHAIN SWAP TEST ===");
console.log("SECRET:", SECRET);
console.log("HASHLOCK:", HASHLOCK);
console.log("ORDER_HASH:", orderHash);
console.log("CURRENT_TIME:", currentTime);
console.log("");

// Destination escrow immutables (Sepolia)
const dstImmutables = {
    orderHash: orderHash,
    hashlock: HASHLOCK,
    maker: DEPLOYER,
    taker: DEPLOYER,
    token: SEPOLIA.testUSDC,
    amount: "1000000000000000000", // 1 USDC
    safetyDeposit: "100000000000000000", // 0.1 ETH
    timelocks:
        "0x" +
        [
            currentTime.toString(16).padStart(8, "0"),
            (300).toString(16).padStart(8, "0"), // srcWithdrawal (5min)
            (600).toString(16).padStart(8, "0"), // srcPublicWithdrawal (10min)
            (1800).toString(16).padStart(8, "0"), // srcCancellation (30min)
            (3600).toString(16).padStart(8, "0"), // srcPublicCancellation (1hr)
            (300).toString(16).padStart(8, "0"), // dstWithdrawal (5min)
            (600).toString(16).padStart(8, "0"), // dstPublicWithdrawal (10min)
            (1800).toString(16).padStart(8, "0"), // dstCancellation (30min)
        ]
            .reverse()
            .join(""),
};

console.log("=== STEP-BY-STEP COMMANDS ===");
console.log("");

console.log("# STEP 1: Approve USDC to Escrow Factory (Sepolia)");
console.log(
    `cast send ${SEPOLIA.testUSDC} "approve(address,uint256)" ${SEPOLIA.escrowFactory} ${dstImmutables.amount} --rpc-url $SEPOLIA_RPC_URL --keystore ~/.foundry/keystores/deployerKey`
);
console.log("");

console.log("# STEP 2: Create Destination Escrow (Sepolia)");
console.log(
    `cast send ${
        SEPOLIA.escrowFactory
    } "createDstEscrow((bytes32,bytes32,address,address,address,uint256,uint256,uint256),uint256)" "(${
        dstImmutables.orderHash
    },${dstImmutables.hashlock},${dstImmutables.maker},${dstImmutables.taker},${
        dstImmutables.token
    },${dstImmutables.amount},${dstImmutables.safetyDeposit},${
        dstImmutables.timelocks
    })" ${currentTime + 1800} --value ${
        dstImmutables.safetyDeposit
    } --rpc-url $SEPOLIA_RPC_URL --keystore ~/.foundry/keystores/deployerKey`
);
console.log("");

console.log("# STEP 3: Get Destination Escrow Address");
console.log(
    `cast call ${SEPOLIA.escrowFactory} "addressOfEscrowDst((bytes32,bytes32,address,address,address,uint256,uint256,uint256))" "(${dstImmutables.orderHash},${dstImmutables.hashlock},${dstImmutables.maker},${dstImmutables.taker},${dstImmutables.token},${dstImmutables.amount},${dstImmutables.safetyDeposit},${dstImmutables.timelocks})" --rpc-url $SEPOLIA_RPC_URL`
);
console.log("");

// Source escrow immutables (Monad)
const srcImmutables = {
    ...dstImmutables,
    token: MONAD.feeToken,
    amount: "2000000000000000000", // 2 FEE tokens
};

console.log("# STEP 4: Get Source Escrow Address (Monad)");
console.log(
    `cast call ${MONAD.escrowFactory} "addressOfEscrowSrc((bytes32,bytes32,address,address,address,uint256,uint256,uint256))" "(${srcImmutables.orderHash},${srcImmutables.hashlock},${srcImmutables.maker},${srcImmutables.taker},${srcImmutables.token},${srcImmutables.amount},${srcImmutables.safetyDeposit},${srcImmutables.timelocks})" --rpc-url https://testnet-rpc.monad.xyz`
);
console.log("");

console.log("# STEP 5: Send FEE Tokens to Source Escrow (Monad)");
console.log(
    `cast send ${MONAD.feeToken} "transfer(address,uint256)" <SRC_ESCROW_ADDRESS> ${srcImmutables.amount} --rpc-url https://testnet-rpc.monad.xyz --keystore ~/.foundry/keystores/deployerKey`
);
console.log("");

console.log("# STEP 6: Send Safety Deposit ETH to Source Escrow (Monad)");
console.log(
    `cast send <SRC_ESCROW_ADDRESS> --value ${srcImmutables.safetyDeposit} --rpc-url https://testnet-rpc.monad.xyz --keystore ~/.foundry/keystores/deployerKey`
);
console.log("");

console.log("=== WAIT 5 MINUTES FOR TIMELOCKS ===");
console.log(`Withdrawal available at: ${new Date((currentTime + 300) * 1000)}`);
console.log("");

console.log(
    "# STEP 7: Withdraw from Destination Escrow (Sepolia) - Reveals Secret"
);
console.log(
    `cast send <DST_ESCROW_ADDRESS> "withdraw(bytes32,(bytes32,bytes32,address,address,address,uint256,uint256,uint256))" ${SECRET} "(${dstImmutables.orderHash},${dstImmutables.hashlock},${dstImmutables.maker},${dstImmutables.taker},${dstImmutables.token},${dstImmutables.amount},${dstImmutables.safetyDeposit},${dstImmutables.timelocks})" --rpc-url $SEPOLIA_RPC_URL --keystore ~/.foundry/keystores/deployerKey`
);
console.log("");

console.log("# STEP 8: Withdraw from Source Escrow (Monad) - Completes Swap");
console.log(
    `cast send <SRC_ESCROW_ADDRESS> "withdraw(bytes32,(bytes32,bytes32,address,address,address,uint256,uint256,uint256))" ${SECRET} "(${srcImmutables.orderHash},${srcImmutables.hashlock},${srcImmutables.maker},${srcImmutables.taker},${srcImmutables.token},${srcImmutables.amount},${srcImmutables.safetyDeposit},${srcImmutables.timelocks})" --rpc-url https://testnet-rpc.monad.xyz --keystore ~/.foundry/keystores/deployerKey`
);
console.log("");

console.log("=== VERIFICATION COMMANDS ===");
console.log("# Check balances after swap");
console.log(
    `cast call ${SEPOLIA.testUSDC} "balanceOf(address)" ${DEPLOYER} --rpc-url $SEPOLIA_RPC_URL`
);
console.log(
    `cast call ${MONAD.feeToken} "balanceOf(address)" ${DEPLOYER} --rpc-url https://testnet-rpc.monad.xyz`
);
