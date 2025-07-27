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
            console.log("Run 1_SetupCrossChainSwap.s.sol first");
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

        console.log(unicode"✅ Loaded swap state from swap_state.json");

        return state;
    }

    function checkTimelockStatus(SwapState memory state) internal {
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

    function checkEscrowStates(SwapState memory state) internal {
        // Check Sepolia destination escrow
        console.log("Checking Sepolia destination escrow...");
        vm.createSelectFork(vm.envString("SEPOLIA_RPC_URL"));

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
        }
        console.log("");

        // Check Monad source escrow
        console.log("Checking Monad source escrow...");
        vm.createSelectFork(vm.envString("MONAD_RPC_URL"));

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
        }
    }

    function assessReadiness(SwapState memory state) internal {
        uint256 currentTime = block.timestamp;
        uint256 withdrawalTime = state.deploymentTime + state.timelockDuration;

        // Check timelock
        bool timelockReady = currentTime >= withdrawalTime;

        // Check escrow funding (simplified check)
        vm.createSelectFork(vm.envString("SEPOLIA_RPC_URL"));
        bool dstFunded = IERC20(state.sepoliaToken).balanceOf(state.dstEscrow) >= state.dstAmount;

        vm.createSelectFork(vm.envString("MONAD_RPC_URL"));
        bool srcFunded = IERC20(state.monadToken).balanceOf(state.srcEscrow) >= state.srcAmount;

        console.log("Readiness checklist:");
        console.log(unicode"  ⏰ Timelock elapsed:", timelockReady ? unicode"✅" : unicode"❌");
        console.log(unicode"  💰 Destination funded:", dstFunded ? unicode"✅" : unicode"❌");
        console.log(unicode"  💰 Source funded:", srcFunded ? unicode"✅" : unicode"❌");

        if (timelockReady && dstFunded && srcFunded) {
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
                console.log("Wait", remaining, "more seconds for timelock");
            }

            if (!dstFunded) {
                console.log("Destination escrow needs funding");
            }

            if (!srcFunded) {
                console.log("Source escrow needs funding");
            }

            console.log("");
            console.log("Re-run this script to check status again:");
            console.log("forge script script/2_CheckSwapStatus.s.sol");
        }
    }
}
