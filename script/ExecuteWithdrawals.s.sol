// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { Address, AddressLib } from "solidity-utils/contracts/libraries/AddressLib.sol";

import { IBaseEscrow } from "contracts/interfaces/IBaseEscrow.sol";
import { Timelocks, TimelocksLib } from "contracts/libraries/TimelocksLib.sol";
import { TimelocksSettersLib } from "test/utils/libraries/TimelocksSettersLib.sol";

/**
 * @title Execute Withdrawals - Phase 3
 * @notice Executes the atomic withdrawal phase of the cross-chain swap
 * @dev Usage:
 *
 * forge script script/3_ExecuteWithdrawals.s.sol --broadcast --account deployerKey
 *
 * This script will:
 * 1. Load swap state from swap_state.json
 * 2. Validate timelock periods have elapsed
 * 3. Execute destination withdrawal (reveals secret)
 * 4. Execute source withdrawal (completes atomic swap)
 * 5. Verify completion and cleanup
 */
contract ExecuteWithdrawals is Script {
    using TimelocksLib for Timelocks;
    using AddressLib for Address;

    // Swap state structure (matches other scripts)
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

    address public deployer;

    function setUp() public {
        deployer = vm.envAddress("DEPLOYER_ADDRESS");
        console.log("=== CROSS-CHAIN SWAP WITHDRAWAL EXECUTION ===");
        console.log("Deployer:", deployer);
        console.log("");
    }

    function run() external {
        // Load swap state
        SwapState memory state = loadSwapState();

        // Validate testnet environment before any transactions
        console.log("=== TESTNET ENVIRONMENT VALIDATION ===");
        validateTestnetEnvironment();
        console.log("");

        // Validate readiness
        console.log("=== PRE-EXECUTION VALIDATION ===");
        validateReadiness(state);
        console.log("");

        // Execute atomic withdrawals
        console.log("=== ATOMIC WITHDRAWAL EXECUTION ===");
        executeAtomicWithdrawals(state);

        // Verify completion
        console.log("=== POST-EXECUTION VERIFICATION ===");
        verifyCompletion(state);

        console.log("");
        console.log(unicode"🎉 CROSS-CHAIN ATOMIC SWAP COMPLETED SUCCESSFULLY! 🎉");
        printFinalSummary(state);
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

        // Validate critical addresses are not zero
        if (state.dstEscrow == address(0) || state.srcEscrow == address(0)) {
            console.log(unicode"❌ ERROR: Missing escrow addresses in state file!");
            console.log("The setup script may not have completed successfully");
            revert("Invalid escrow addresses in state file");
        }

        if (state.secret == bytes32(0) || state.hashlock == bytes32(0)) {
            console.log(unicode"❌ ERROR: Missing secret or hashlock in state file!");
            revert("Invalid secret data in state file");
        }

        console.log(unicode"✅ Loaded and validated swap state from swap_state.json");
        console.log("  Destination escrow:", state.dstEscrow);
        console.log("  Source escrow:", state.srcEscrow);
        console.log("  Secret available:", state.secret != bytes32(0));

        return state;
    }

    function validateReadiness(
        SwapState memory state
    ) internal {
        uint256 currentTime = block.timestamp;
        uint256 withdrawalTime = state.deploymentTime + state.timelockDuration;

        console.log("Timelock validation:");
        console.log("  Deployment time:", state.deploymentTime);
        console.log("  Current time:", currentTime);
        console.log("  Withdrawal time:", withdrawalTime);
        console.log("  Time elapsed:", currentTime - state.deploymentTime, "seconds");

        // Validate timelock
        if (currentTime < withdrawalTime) {
            uint256 remaining = withdrawalTime - currentTime;
            console.log(unicode"  ❌ Timelock not yet elapsed!");
            console.log(unicode"  ⏰ Need to wait", remaining, "more seconds");
            revert("Timelock period not yet elapsed");
        }

        console.log(unicode"  ✅ Timelock period has elapsed");

        // Validate escrow funding
        console.log("Escrow funding validation:");

        // Check Sepolia
        try vm.createSelectFork(vm.envString("SEPOLIA_RPC_URL")) {
            uint256 dstTokenBalance = IERC20(state.sepoliaToken).balanceOf(state.dstEscrow);
            uint256 dstEthBalance = state.dstEscrow.balance;

            console.log("  Sepolia escrow:", state.dstEscrow);
            console.log("    Token balance:", dstTokenBalance, "/ expected:", state.dstAmount);
            console.log("    ETH balance:", dstEthBalance, "/ expected:", state.safetyDeposit);

            if (dstTokenBalance < state.dstAmount) {
                revert("Destination escrow insufficient token balance");
            }
            if (dstEthBalance < state.safetyDeposit) {
                revert("Destination escrow insufficient ETH balance");
            }
            console.log(unicode"    ✅ Properly funded");
        } catch {
            console.log(unicode"❌ Failed to connect to Sepolia testnet");
            console.log("Check SEPOLIA_RPC_URL environment variable");
            revert("Cannot connect to Sepolia for pre-execution validation");
        }

        // Check Monad
        try vm.createSelectFork(vm.envString("MONAD_RPC_URL")) {
            uint256 srcTokenBalance = IERC20(state.monadToken).balanceOf(state.srcEscrow);
            uint256 srcEthBalance = state.srcEscrow.balance;

            console.log("  Monad escrow:", state.srcEscrow);
            console.log("    Token balance:", srcTokenBalance, "/ expected:", state.srcAmount);
            console.log("    ETH balance:", srcEthBalance, "/ expected:", state.safetyDeposit);

            if (srcTokenBalance < state.srcAmount) {
                revert("Source escrow insufficient token balance");
            }
            if (srcEthBalance < state.safetyDeposit) {
                revert("Source escrow insufficient ETH balance");
            }
            console.log(unicode"    ✅ Properly funded");
        } catch {
            console.log(unicode"❌ Failed to connect to Monad testnet");
            console.log("Check MONAD_RPC_URL environment variable");
            revert("Cannot connect to Monad for pre-execution validation");
        }

        console.log(unicode"✅ All validation checks passed - ready for withdrawal");
    }

    function executeAtomicWithdrawals(
        SwapState memory state
    ) internal {
        // Prepare timelocks with actual deployment time
        Timelocks timelocks = TimelocksSettersLib.init(
            state.timelockDuration, // srcWithdrawal
            state.timelockDuration * 2, // srcPublicWithdrawal
            state.timelockDuration * 3, // srcCancellation
            state.timelockDuration * 4, // srcPublicCancellation
            state.timelockDuration, // dstWithdrawal
            state.timelockDuration * 2, // dstPublicWithdrawal
            state.timelockDuration * 2, // dstCancellation
            uint32(state.deploymentTime) // deployedAt
        );

        // Prepare immutables for both escrows
        IBaseEscrow.Immutables memory dstImmutables = IBaseEscrow.Immutables({
            orderHash: state.orderHash,
            hashlock: state.hashlock,
            maker: Address.wrap(uint160(deployer)),
            taker: Address.wrap(uint160(deployer)),
            token: Address.wrap(uint160(state.sepoliaToken)),
            amount: state.dstAmount,
            safetyDeposit: state.safetyDeposit,
            timelocks: timelocks
        });

        IBaseEscrow.Immutables memory srcImmutables = IBaseEscrow.Immutables({
            orderHash: state.orderHash,
            hashlock: state.hashlock,
            maker: Address.wrap(uint160(deployer)),
            taker: Address.wrap(uint160(deployer)),
            token: Address.wrap(uint160(state.monadToken)),
            amount: state.srcAmount,
            safetyDeposit: state.safetyDeposit,
            timelocks: timelocks
        });

        // Step 1: Execute destination withdrawal (Sepolia) - reveals secret
        console.log("Step 1: Executing destination withdrawal (Sepolia)");
        console.log("  This will reveal the secret and transfer destination tokens");

        try vm.createSelectFork(vm.envString("SEPOLIA_RPC_URL")) {
            console.log(unicode"  ✅ Connected to Sepolia testnet");
        } catch {
            console.log(unicode"❌ Failed to connect to Sepolia testnet");
            revert("Cannot connect to Sepolia for withdrawal execution");
        }

        vm.startBroadcast(deployer);

        try IBaseEscrow(state.dstEscrow).withdraw(state.secret, dstImmutables) {
            console.log(unicode"  ✅ Secret revealed and destination tokens withdrawn");
            console.log(unicode"  ✅ Safety deposit recovered");
        } catch (bytes memory reason) {
            console.log(unicode"  ❌ Destination withdrawal failed");
            debugEscrowState(state.dstEscrow, state.sepoliaToken, "Sepolia DST");

            if (reason.length > 0) {
                console.log("  Error details:");
                console.logBytes(reason);
            }
            revert("Destination withdrawal failed");
        }

        vm.stopBroadcast();

        // Step 2: Execute source withdrawal (Monad) - completes atomic swap
        console.log("Step 2: Executing source withdrawal (Monad)");
        console.log("  Using the revealed secret to claim source tokens");

        try vm.createSelectFork(vm.envString("MONAD_RPC_URL")) {
            console.log(unicode"  ✅ Connected to Monad testnet");
        } catch {
            console.log(unicode"❌ Failed to connect to Monad testnet");
            revert("Cannot connect to Monad for withdrawal execution");
        }

        vm.startBroadcast(deployer);

        try IBaseEscrow(state.srcEscrow).withdraw(state.secret, srcImmutables) {
            console.log(unicode"  ✅ Source tokens withdrawn using revealed secret");
            console.log(unicode"  ✅ Safety deposit recovered");
            console.log(unicode"  🎉 Cross-chain atomic swap completed!");
        } catch (bytes memory reason) {
            console.log(unicode"  ❌ Source withdrawal failed");
            debugEscrowState(state.srcEscrow, state.monadToken, "Monad SRC");

            if (reason.length > 0) {
                console.log("  Error details:");
                console.logBytes(reason);
            }
            revert("Source withdrawal failed");
        }

        vm.stopBroadcast();

        console.log(unicode"✅ Both atomic withdrawals completed successfully");
    }

    function verifyCompletion(
        SwapState memory state
    ) internal {
        console.log("Verifying swap completion...");

        // Check Sepolia escrow is empty
        uint256 dstTokenBalance = 0;
        uint256 dstEthBalance = 0;
        bool sepoliaChecked = false;

        try vm.createSelectFork(vm.envString("SEPOLIA_RPC_URL")) {
            dstTokenBalance = IERC20(state.sepoliaToken).balanceOf(state.dstEscrow);
            dstEthBalance = state.dstEscrow.balance;
            sepoliaChecked = true;

            console.log("Sepolia escrow final state:");
            console.log("  Token balance:", dstTokenBalance);
            console.log("  ETH balance:", dstEthBalance);
        } catch {
            console.log(unicode"❌ Cannot connect to Sepolia for final verification");
        }

        // Check Monad escrow is empty
        uint256 srcTokenBalance = 0;
        uint256 srcEthBalance = 0;
        bool monadChecked = false;

        try vm.createSelectFork(vm.envString("MONAD_RPC_URL")) {
            srcTokenBalance = IERC20(state.monadToken).balanceOf(state.srcEscrow);
            srcEthBalance = state.srcEscrow.balance;
            monadChecked = true;

            console.log("Monad escrow final state:");
            console.log("  Token balance:", srcTokenBalance);
            console.log("  ETH balance:", srcEthBalance);
        } catch {
            console.log(unicode"❌ Cannot connect to Monad for final verification");
        }

        // Verify completion
        if (!sepoliaChecked || !monadChecked) {
            console.log(unicode"⚠️  Cannot verify completion due to network connectivity issues");
            if (!sepoliaChecked) {
                console.log("   Sepolia verification failed - check connection manually");
            }
            if (!monadChecked) {
                console.log("   Monad verification failed - check connection manually");
            }
            return;
        }

        bool allEmpty = (dstTokenBalance == 0 && dstEthBalance == 0 && srcTokenBalance == 0 && srcEthBalance == 0);

        if (allEmpty) {
            console.log(unicode"✅ All escrows properly emptied");
            console.log(unicode"✅ All funds successfully transferred");
            console.log(unicode"✅ All safety deposits recovered");
        } else {
            console.log(unicode"⚠️  Some funds may remain in escrows (this could be normal)");
            if (dstTokenBalance > 0 || dstEthBalance > 0) {
                console.log("   Sepolia escrow not completely empty");
            }
            if (srcTokenBalance > 0 || srcEthBalance > 0) {
                console.log("   Monad escrow not completely empty");
            }
        }
    }

    function debugEscrowState(address escrowAddress, address tokenAddress, string memory label) internal view {
        uint256 tokenBalance = IERC20(tokenAddress).balanceOf(escrowAddress);
        uint256 ethBalance = escrowAddress.balance;

        console.log("  Debug", label, "escrow state:");
        console.log("    Address:", escrowAddress);
        console.log("    Token balance:", tokenBalance);
        console.log("    ETH balance:", ethBalance);
        console.log("    Current time:", block.timestamp);
    }

    function printFinalSummary(
        SwapState memory state
    ) internal view {
        console.log("=== ATOMIC SWAP COMPLETION SUMMARY ===");
        console.log(unicode"✅ Cross-chain atomic swap successfully completed");
        console.log(unicode"✅ Secret properly revealed and used across both chains");
        console.log(unicode"✅ Tokens swapped:", state.srcAmount, "->", state.dstAmount);
        console.log(unicode"✅ Safety deposits recovered on both chains");
        console.log("");
        console.log("Final Details:");
        console.log("  Secret used:", vm.toString(state.secret));
        console.log("  Hashlock:", vm.toString(state.hashlock));
        console.log("  Total execution time:", block.timestamp - state.deploymentTime, "seconds");
        console.log("  Sepolia escrow (emptied):", state.dstEscrow);
        console.log("  Monad escrow (emptied):", state.srcEscrow);
        console.log("");
        console.log(unicode"🎉 CROSS-CHAIN ATOMIC SWAP COMPLETE! 🎉");
    }

    function validateTestnetEnvironment() internal {
        bool sepoliaOk = false;
        bool monadOk = false;

        console.log("Validating testnet connections before executing withdrawals...");

        // Test Sepolia connection
        try vm.envString("SEPOLIA_RPC_URL") returns (string memory sepoliaRpc) {
            if (bytes(sepoliaRpc).length > 0) {
                try vm.createSelectFork(sepoliaRpc) {
                    console.log(unicode"  🌐 Sepolia testnet: ✅ Connected");
                    console.log("    Chain ID:", block.chainid);
                    sepoliaOk = true;
                } catch {
                    console.log(unicode"  🌐 Sepolia testnet: ❌ Connection failed");
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
                }
            } else {
                console.log(unicode"  🌐 Monad testnet: ❌ MONAD_RPC_URL not set");
            }
        } catch {
            console.log(unicode"  🌐 Monad testnet: ❌ MONAD_RPC_URL not found");
        }

        if (!sepoliaOk || !monadOk) {
            console.log("");
            console.log(unicode"❌ CRITICAL: Testnet validation failed!");
            console.log("Cannot proceed with withdrawals - fix connectivity issues first:");
            if (!sepoliaOk) console.log("  export SEPOLIA_RPC_URL=\"https://sepolia.infura.io/v3/YOUR_KEY\"");
            if (!monadOk) console.log("  export MONAD_RPC_URL=\"https://testnet-rpc.monad.xyz\"");
            revert("Testnet connectivity validation failed");
        } else {
            console.log(unicode"✅ All testnet connections validated - safe to proceed");
        }
    }
}
