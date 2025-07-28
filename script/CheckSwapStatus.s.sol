// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/**
 * @title Check Swap Status - Phase 2
 * @notice Monitors timelock status and escrow funding before withdrawal
 * @dev Usage:
 *
 * forge script script/2_CheckSwapStatus.s.sol
 *
 * This script will:
 * 1. Load swap state from swap_state.json
 * 2. Check timelock status on both networks
 * 3. Verify escrow funding
 * 4. Indicate readiness for withdrawal execution
 */
contract CheckSwapStatus is Script {
    // Swap state structure (matches setup script)
    struct SwapState {
        bytes32 secret;
        bytes32 hashlock;
        bytes32 orderHash;
        uint256 deploymentTime;
        uint256 srcAmount;
        uint256 dstAmount;
        uint256 safetyDeposit;
        address dstEscrow;
        address srcEscrow;
        address sepoliaFactory;
        address sepoliaToken;
        address monadFactory;
        address monadToken;
        uint32 timelockDuration;
    }

    function run() external {
        console.log("=== CROSS-CHAIN SWAP STATUS CHECK ===");
        console.log("");

        // Load swap state
        SwapState memory state = loadSwapState();

        // Validate testnet environment
        console.log("=== TESTNET VALIDATION ===");
        validateTestnetEnvironment();
        console.log("");

        // Check timing
        console.log("=== TIMELOCK STATUS ===");
        checkTimelockStatus(state);
        console.log("");

        // Check escrow states
        console.log("=== ESCROW STATUS ===");
        checkEscrowStates(state);
        console.log("");

        // Final readiness assessment
        console.log("=== READINESS ASSESSMENT ===");
        assessReadiness(state);
    }

    function loadSwapState() internal view returns (SwapState memory state) {
        string memory json;

        try vm.readFile("swap_state.json") returns (string memory content) {
            json = content;
        } catch {
            console.log(unicode"❌ ERROR: swap_state.json not found!");
            console.log("Run SetupCrossChainSwap.s.sol first to generate the state file");
            revert("Swap state file not found");
        }

        // Parse JSON into struct
        state.secret = vm.parseJsonBytes32(json, ".secret");
        state.hashlock = vm.parseJsonBytes32(json, ".hashlock");
        state.orderHash = vm.parseJsonBytes32(json, ".orderHash");
        state.deploymentTime = vm.parseJsonUint(json, ".deploymentTime");
        state.srcAmount = vm.parseJsonUint(json, ".srcAmount");
        state.dstAmount = vm.parseJsonUint(json, ".dstAmount");
        state.safetyDeposit = vm.parseJsonUint(json, ".safetyDeposit");
        state.dstEscrow = vm.parseJsonAddress(json, ".dstEscrow");
        state.srcEscrow = vm.parseJsonAddress(json, ".srcEscrow");
        state.sepoliaFactory = vm.parseJsonAddress(json, ".sepoliaFactory");
        state.sepoliaToken = vm.parseJsonAddress(json, ".sepoliaToken");
        state.monadFactory = vm.parseJsonAddress(json, ".monadFactory");
        state.monadToken = vm.parseJsonAddress(json, ".monadToken");
        state.timelockDuration = uint32(vm.parseJsonUint(json, ".timelockDuration"));

        // Validate critical addresses are not zero
        if (state.dstEscrow == address(0) || state.srcEscrow == address(0)) {
            console.log(unicode"❌ ERROR: Missing escrow addresses in state file!");
            console.log("The setup script may not have completed successfully");
            revert("Invalid escrow addresses in state file");
        }

        console.log(unicode"✅ Loaded and validated swap state from swap_state.json");
        console.log("  Destination escrow:", state.dstEscrow);
        console.log("  Source escrow:", state.srcEscrow);
        console.log("  Deployment time:", state.deploymentTime);

        return state;
    }

    function checkTimelockStatus(
        SwapState memory state
    ) internal view {
        uint256 currentTime = block.timestamp;
        uint256 withdrawalTime = state.deploymentTime + state.timelockDuration;

        console.log("Deployment time:", state.deploymentTime);
        console.log("Current time:", currentTime);
        console.log("Timelock duration:", state.timelockDuration, "seconds");
        console.log("Withdrawal available at:", withdrawalTime);

        if (currentTime >= withdrawalTime) {
            uint256 elapsed = currentTime - state.deploymentTime;
            console.log(unicode"✅ TIMELOCK ELAPSED");
            console.log("   Time elapsed:", elapsed, "seconds");
            console.log("   Withdrawals are now available!");
        } else {
            uint256 remaining = withdrawalTime - currentTime;
            console.log(unicode"⏰ TIMELOCK ACTIVE");
            console.log("   Time remaining:", remaining, "seconds");
            console.log("   Wait before withdrawal");
        }
    }

    function checkEscrowStates(
        SwapState memory state
    ) internal {
        // Check Sepolia destination escrow
        console.log("Checking Sepolia destination escrow...");

        try vm.createSelectFork(vm.envString("SEPOLIA_RPC_URL")) {
            uint256 dstTokenBalance = IERC20(state.sepoliaToken).balanceOf(state.dstEscrow);
            uint256 dstEthBalance = state.dstEscrow.balance;

            console.log("  Address:", state.dstEscrow);
            console.log("  Token balance:", dstTokenBalance);
            console.log("  Expected token:", state.dstAmount);
            console.log("  ETH balance:", dstEthBalance);
            console.log("  Expected ETH:", state.safetyDeposit);

            if (dstTokenBalance >= state.dstAmount && dstEthBalance >= state.safetyDeposit) {
                console.log(unicode"  ✅ Properly funded");
            } else {
                console.log(unicode"  ❌ Insufficient funding");
                if (dstTokenBalance < state.dstAmount) {
                    console.log("    Missing token amount:", state.dstAmount - dstTokenBalance);
                }
                if (dstEthBalance < state.safetyDeposit) {
                    console.log("    Missing ETH amount:", state.safetyDeposit - dstEthBalance);
                }
            }
        } catch {
            console.log(unicode"  ❌ Failed to connect to Sepolia testnet");
            console.log("    Check SEPOLIA_RPC_URL environment variable");
        }
        console.log("");

        // Check Monad source escrow
        console.log("Checking Monad source escrow...");

        try vm.createSelectFork(vm.envString("MONAD_RPC_URL")) {
            uint256 srcTokenBalance = IERC20(state.monadToken).balanceOf(state.srcEscrow);
            uint256 srcEthBalance = state.srcEscrow.balance;

            console.log("  Address:", state.srcEscrow);
            console.log("  Token balance:", srcTokenBalance);
            console.log("  Expected token:", state.srcAmount);
            console.log("  ETH balance:", srcEthBalance);
            console.log("  Expected ETH:", state.safetyDeposit);

            if (srcTokenBalance >= state.srcAmount && srcEthBalance >= state.safetyDeposit) {
                console.log(unicode"  ✅ Properly funded");
            } else {
                console.log(unicode"  ❌ Insufficient funding");
                if (srcTokenBalance < state.srcAmount) {
                    console.log("    Missing token amount:", state.srcAmount - srcTokenBalance);
                }
                if (srcEthBalance < state.safetyDeposit) {
                    console.log("    Missing ETH amount:", state.safetyDeposit - srcEthBalance);
                }
            }
        } catch {
            console.log(unicode"  ❌ Failed to connect to Monad testnet");
            console.log("    Check MONAD_RPC_URL environment variable");
        }
    }

    function assessReadiness(
        SwapState memory state
    ) internal {
        uint256 currentTime = block.timestamp;
        uint256 withdrawalTime = state.deploymentTime + state.timelockDuration;

        // Check timelock
        bool timelockReady = currentTime >= withdrawalTime;

        // Check escrow funding with testnet error handling
        bool dstFunded = false;
        bool srcFunded = false;
        bool dstConnected = false;
        bool srcConnected = false;

        try vm.createSelectFork(vm.envString("SEPOLIA_RPC_URL")) {
            dstFunded = IERC20(state.sepoliaToken).balanceOf(state.dstEscrow) >= state.dstAmount &&
                       state.dstEscrow.balance >= state.safetyDeposit;
            dstConnected = true;
        } catch {
            console.log(unicode"⚠️  Cannot connect to Sepolia testnet for final check");
        }

        try vm.createSelectFork(vm.envString("MONAD_RPC_URL")) {
            srcFunded = IERC20(state.monadToken).balanceOf(state.srcEscrow) >= state.srcAmount &&
                       state.srcEscrow.balance >= state.safetyDeposit;
            srcConnected = true;
        } catch {
            console.log(unicode"⚠️  Cannot connect to Monad testnet for final check");
        }

        console.log("Readiness checklist:");
        console.log(unicode"  ⏰ Timelock elapsed:", timelockReady ? unicode"✅" : unicode"❌");
        console.log(unicode"  🌐 Sepolia connection:", dstConnected ? unicode"✅" : unicode"❌");
        console.log(unicode"  💰 Destination funded:", dstFunded ? unicode"✅" : unicode"❌");
        console.log(unicode"  🌐 Monad connection:", srcConnected ? unicode"✅" : unicode"❌");
        console.log(unicode"  💰 Source funded:", srcFunded ? unicode"✅" : unicode"❌");

        if (timelockReady && dstFunded && srcFunded && dstConnected && srcConnected) {
            console.log("");
            console.log(unicode"🎉 READY FOR WITHDRAWAL! 🎉");
            console.log("");
            console.log("Next step:");
            console.log("forge script script/3_ExecuteWithdrawals.s.sol --broadcast --account deployerKey");
        } else {
            console.log("");
            console.log(unicode"⚠️  NOT READY YET");

            if (!timelockReady) {
                uint256 remaining = withdrawalTime - currentTime;
                console.log(unicode"⏰ Wait", remaining, "more seconds for timelock");
            }

            if (!dstConnected) {
                console.log(unicode"🌐 Fix Sepolia testnet connection (check SEPOLIA_RPC_URL)");
            } else if (!dstFunded) {
                console.log(unicode"💰 Destination escrow needs funding on Sepolia");
            }

            if (!srcConnected) {
                console.log(unicode"🌐 Fix Monad testnet connection (check MONAD_RPC_URL)");
            } else if (!srcFunded) {
                console.log(unicode"💰 Source escrow needs funding on Monad");
            }

            console.log("");
            console.log("Re-run this script to check status again:");
            console.log("forge script script/CheckSwapStatus.s.sol");
        }
    }

    function validateTestnetEnvironment() internal {
        bool sepoliaOk = false;
        bool monadOk = false;

        // Test Sepolia connection
        try vm.envString("SEPOLIA_RPC_URL") returns (string memory sepoliaRpc) {
            if (bytes(sepoliaRpc).length > 0) {
                try vm.createSelectFork(sepoliaRpc) {
                    console.log(unicode"  🌐 Sepolia testnet: ✅ Connected");
                    console.log("    Chain ID:", block.chainid);
                    sepoliaOk = true;
                } catch {
                    console.log(unicode"  🌐 Sepolia testnet: ❌ Connection failed");
                    console.log("    Check RPC URL and network connectivity");
                }
            } else {
                console.log(unicode"  🌐 Sepolia testnet: ❌ SEPOLIA_RPC_URL not set");
            }
        } catch {
            console.log(unicode"  🌐 Sepolia testnet: ❌ SEPOLIA_RPC_URL not found");
        }

        // Test Monad connection
        try vm.envString("MONAD_RPC_URL") returns (string memory monadRpc) {
            if (bytes(monadRpc).length > 0) {
                try vm.createSelectFork(monadRpc) {
                    console.log(unicode"  🌐 Monad testnet: ✅ Connected");
                    console.log("    Chain ID:", block.chainid);
                    monadOk = true;
                } catch {
                    console.log(unicode"  🌐 Monad testnet: ❌ Connection failed");
                    console.log("    Check RPC URL and network connectivity");
                }
            } else {
                console.log(unicode"  🌐 Monad testnet: ❌ MONAD_RPC_URL not set");
            }
        } catch {
            console.log(unicode"  🌐 Monad testnet: ❌ MONAD_RPC_URL not found");
        }

        if (!sepoliaOk || !monadOk) {
            console.log("");
            console.log(unicode"⚠️  Some testnet connections failed!");
            console.log("Set environment variables:");
            if (!sepoliaOk) console.log("  export SEPOLIA_RPC_URL=\"https://sepolia.infura.io/v3/YOUR_KEY\"");
            if (!monadOk) console.log("  export MONAD_RPC_URL=\"https://testnet-rpc.monad.xyz\"");
        } else {
            console.log(unicode"✅ All testnet connections verified");
        }
    }
}
