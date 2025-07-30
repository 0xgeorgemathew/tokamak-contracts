// solhint-disable no-console
// solhint-disable quotes
// solhint-disable-next-line quotes

// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { Vm } from "forge-std/Vm.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { TokenMock } from "solidity-utils/contracts/mocks/TokenMock.sol";
import { Address, AddressLib } from "solidity-utils/contracts/libraries/AddressLib.sol";

import { IBaseEscrow } from "contracts/interfaces/IBaseEscrow.sol";
import { IEscrowFactory } from "contracts/interfaces/IEscrowFactory.sol";
import { Timelocks, TimelocksLib } from "contracts/libraries/TimelocksLib.sol";
import { TimelocksSettersLib } from "test/utils/libraries/TimelocksSettersLib.sol";

/**
 * @title Setup Cross-Chain Swap - Phase 1
 * @notice Sets up escrows on both networks and saves parameters for later execution
 * @dev Usage:
 *
 * forge script script/1_SetupCrossChainSwap.s.sol --broadcast --account deployerKey
 *
 * This script will:
 * 1. Generate swap parameters
 * 2. Create and fund destination escrow on Sepolia
 * 3. Fund source escrow on Monad
 * 4. Save all parameters to swap_state.json for subsequent scripts
 */
contract SetupCrossChainSwap is Script {
    using TimelocksLib for Timelocks;
    using AddressLib for Address;

    // Deployment data structure
    struct DeploymentData {
        address escrowFactory;
        address accessToken;
        address feeToken;
        address swapToken;
        address limitOrderProtocol;
        uint256 chainId;
    }

    // Swap parameters to save
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

    // Configuration
    uint32 constant _TESTNET_TIMELOCK = 60; // 60 seconds for testing
    address public deployer;

    function setUp() public {
        deployer = vm.envAddress("DEPLOYER_ADDRESS");
        console.log("=== CROSS-CHAIN SWAP SETUP ===");
        console.log("Deployer:", deployer);
        console.log("");
    }

    function run() external {
        // Load network configurations
        (DeploymentData memory sepoliaData, DeploymentData memory monadData) = _loadDeploymentConfig();

        // Generate swap parameters
        SwapState memory state = _generateSwapState(sepoliaData, monadData);
        _logSwapState(state);

        // Phase 1: Setup Sepolia destination escrow
        console.log("=== PHASE 1: Sepolia Destination Escrow ===");
        vm.createSelectFork(vm.envString("SEPOLIA_RPC_URL"));
        _setupSepoliaEscrow(state);

        // Phase 2: Setup Monad source escrow
        console.log("=== PHASE 2: Monad Source Escrow ===");
        vm.createSelectFork(vm.envString("MONAD_RPC_URL"));
        _setupMonadEscrow(state);

        // Save state for subsequent scripts
        console.log("=== SAVING SWAP STATE ===");
        _saveSwapState(state);

        console.log("=== SETUP COMPLETED ===");
        console.log("Next steps:");
        console.log("1. Wait 60+ seconds for timelock");
        console.log("2. Run: forge script script/2_CheckSwapStatus.s.sol");
        console.log("3. Run: forge script script/3_ExecuteWithdrawals.s.sol --broadcast");
        console.log("");
        _printSummary(state);
    }

    function _loadDeploymentConfig()
        internal
        view
        returns (DeploymentData memory sepoliaData, DeploymentData memory monadData)
    {
        string memory json;

        try vm.readFile("deployments.json") returns (string memory fileContent) {
            json = fileContent;
        } catch {
            console.log("WARNING: Using fallback addresses");
            return (
                DeploymentData({
                    escrowFactory: 0x6D3002AcE4619162b1231fd33502371e80D2b3EC,
                    accessToken: address(0),
                    feeToken: address(0),
                    swapToken: 0x42312264B1fFdc7a19C7aa9d199D7eE1F94f8b01,
                    limitOrderProtocol: 0xa8D8F5f33af375ba0Eb0Ed15C46DA0757DE21b56,
                    chainId: 11155111
                }),
                DeploymentData({
                    escrowFactory: 0xca024dF3DFc8e23Ce6152c35525cF20F90f4e874,
                    accessToken: address(0),
                    feeToken: address(0),
                    swapToken: 0x3C11bbAB586ad18EE9d53dF47718DBefec7445D0,
                    limitOrderProtocol: 0x689F20F2e2901f32E255e8016Ad9D58b61D353b3,
                    chainId: 10143
                })
            );
        }

        // Parse configuration
        sepoliaData.escrowFactory = vm.parseJsonAddress(json, ".contracts.sepolia.escrowFactory");
        sepoliaData.swapToken = vm.parseJsonAddress(json, ".contracts.sepolia.swapToken");
        sepoliaData.chainId = vm.parseJsonUint(json, ".contracts.sepolia.chainId");

        monadData.escrowFactory = vm.parseJsonAddress(json, ".contracts.monad.escrowFactory");
        monadData.swapToken = vm.parseJsonAddress(json, ".contracts.monad.swapToken");
        monadData.chainId = vm.parseJsonUint(json, ".contracts.monad.chainId");
    }

    function _generateSwapState(
        DeploymentData memory sepoliaData,
        DeploymentData memory monadData
    ) internal view returns (SwapState memory) {
        // Generate deterministic parameters
        uint256 currentTime = block.timestamp;
        bytes32 secret = keccak256(abi.encodePacked(currentTime, deployer, "testnet_v1"));
        bytes32 hashlock = keccak256(abi.encode(secret));
        bytes32 orderHash = keccak256(abi.encodePacked(secret, currentTime, "order_v1"));

        // Swap amounts
        uint256 srcAmount = 1 ether;
        uint256 dstAmount = 0.5 ether;
        uint256 safetyDeposit = 0.01 ether;

        console.log("Generated swap parameters:");
        console.log("Secret:", vm.toString(secret));
        console.log("Hashlock:", vm.toString(hashlock));
        console.log("Order Hash:", vm.toString(orderHash));
        console.log("Source Amount:", srcAmount);
        console.log("Destination Amount:", dstAmount);
        console.log("");

        // Initialize state with placeholder addresses - will be computed in fork contexts
        return SwapState({
            secret: secret,
            hashlock: hashlock,
            orderHash: orderHash,
            deploymentTime: currentTime,
            srcAmount: srcAmount,
            dstAmount: dstAmount,
            safetyDeposit: safetyDeposit,
            dstEscrow: address(0), // Will be computed in Sepolia fork
            srcEscrow: address(0), // Will be computed in Monad fork
            sepoliaFactory: sepoliaData.escrowFactory,
            sepoliaToken: sepoliaData.swapToken,
            monadFactory: monadData.escrowFactory,
            monadToken: monadData.swapToken,
            timelockDuration: _TESTNET_TIMELOCK
        });
    }

    function _setupSepoliaEscrow(
        SwapState memory state
    ) internal {
        // Compute destination escrow address in Sepolia fork context
        console.log("Computing destination escrow address on Sepolia...");
        console.log("Sepolia factory:", state.sepoliaFactory);

        Timelocks timelocks = TimelocksSettersLib.init(
            state.timelockDuration, // srcWithdrawal
            state.timelockDuration * 2, // srcPublicWithdrawal
            state.timelockDuration * 3, // srcCancellation
            state.timelockDuration * 4, // srcPublicCancellation
            state.timelockDuration, // dstWithdrawal
            state.timelockDuration * 2, // dstPublicWithdrawal
            state.timelockDuration * 2, // dstCancellation
            uint32(state.deploymentTime) // deployedAt = deployment timestamp
        );

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

        try IEscrowFactory(state.sepoliaFactory).addressOfEscrowDst(dstImmutables) returns (address addr) {
            state.dstEscrow = addr;
            console.log(unicode"  ✓ Destination escrow computed:", state.dstEscrow);
        } catch {
            console.log("ERROR: Failed to compute destination escrow address on Sepolia");
            revert("Destination escrow computation failed on Sepolia testnet");
        }

        vm.startBroadcast(deployer);

        // Setup tokens
        console.log("Setting up Sepolia tokens...");
        TokenMock sepoliaToken = TokenMock(state.sepoliaToken);
        sepoliaToken.mint(deployer, 10 ether);
        sepoliaToken.approve(state.sepoliaFactory, state.dstAmount);
        console.log(unicode"  ✓ Minted 10 tokens");
        console.log(unicode"  ✓ Approved", state.dstAmount, "tokens");

        // Create destination escrow
        console.log("Creating destination escrow...");
        uint256 srcCancellationTimestamp = block.timestamp + state.timelockDuration * 3;

        IEscrowFactory(state.sepoliaFactory).createDstEscrow{ value: state.safetyDeposit }(
            dstImmutables, srcCancellationTimestamp
        );

        // Update deployment time to actual block timestamp
        state.deploymentTime = block.timestamp;

        console.log(unicode"  ✓ Destination escrow created:", state.dstEscrow);
        console.log(unicode"  ✓ Safety deposit sent:", state.safetyDeposit);
        console.log(unicode"  ✓ Deployment time:", state.deploymentTime);

        vm.stopBroadcast();
        console.log("Sepolia setup completed");
        console.log("");
    }

    function _setupMonadEscrow(
        SwapState memory state
    ) internal {
        // Compute source escrow address in Monad fork context
        console.log("Computing source escrow address on Monad...");
        console.log("Monad factory:", state.monadFactory);

        Timelocks timelocks = TimelocksSettersLib.init(
            state.timelockDuration, // srcWithdrawal
            state.timelockDuration * 2, // srcPublicWithdrawal
            state.timelockDuration * 3, // srcCancellation
            state.timelockDuration * 4, // srcPublicCancellation
            state.timelockDuration, // dstWithdrawal
            state.timelockDuration * 2, // dstPublicWithdrawal
            state.timelockDuration * 2, // dstCancellation
            uint32(state.deploymentTime) // deployedAt = deployment timestamp
        );

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

        try IEscrowFactory(state.monadFactory).addressOfEscrowSrc(srcImmutables) returns (address addr) {
            state.srcEscrow = addr;
            console.log(unicode"  ✓ Source escrow computed:", state.srcEscrow);
        } catch {
            console.log("ERROR: Failed to compute source escrow address on Monad");
            revert("Source escrow computation failed on Monad testnet");
        }

        vm.startBroadcast(deployer);

        // Setup tokens
        console.log("Setting up Monad tokens...");
        TokenMock monadToken = TokenMock(state.monadToken);
        monadToken.mint(deployer, 10 ether);
        console.log(unicode"  ✓ Minted 10 tokens");

        // Fund source escrow
        console.log("Funding source escrow...");
        monadToken.transfer(state.srcEscrow, state.srcAmount);
        (bool success,) = state.srcEscrow.call{ value: state.safetyDeposit }("");
        if (!success) revert("Failed to send safety deposit");

        console.log(unicode"  ✓ Transferred", state.srcAmount, "tokens to:", state.srcEscrow);
        console.log(unicode"  ✓ Safety deposit sent:", state.safetyDeposit);

        // Verify funding
        uint256 tokenBalance = monadToken.balanceOf(state.srcEscrow);
        uint256 ethBalance = state.srcEscrow.balance;
        console.log(unicode"  ✓ Escrow token balance:", tokenBalance);
        console.log(unicode"  ✓ Escrow ETH balance:", ethBalance);

        vm.stopBroadcast();
        console.log("Monad setup completed");
        console.log("");
    }

    function _saveSwapState(
        SwapState memory state
    ) internal {
        string memory json = string.concat(
            "{\n",
            '  "secret": "',
            vm.toString(state.secret),
            '",\n',
            '  "hashlock": "',
            vm.toString(state.hashlock),
            '",\n',
            '  "orderHash": "',
            vm.toString(state.orderHash),
            '",\n',
            '  "deploymentTime": ',
            vm.toString(state.deploymentTime),
            ",\n",
            '  "srcAmount": "',
            vm.toString(state.srcAmount),
            '",\n',
            '  "dstAmount": "',
            vm.toString(state.dstAmount),
            '",\n',
            '  "safetyDeposit": "',
            vm.toString(state.safetyDeposit),
            '",\n',
            '  "dstEscrow": "',
            vm.toString(state.dstEscrow),
            '",\n',
            '  "srcEscrow": "',
            vm.toString(state.srcEscrow),
            '",\n',
            '  "sepoliaFactory": "',
            vm.toString(state.sepoliaFactory),
            '",\n',
            '  "sepoliaToken": "',
            vm.toString(state.sepoliaToken),
            '",\n',
            '  "monadFactory": "',
            vm.toString(state.monadFactory),
            '",\n',
            '  "monadToken": "',
            vm.toString(state.monadToken),
            '",\n',
            '  "timelockDuration": ',
            vm.toString(state.timelockDuration),
            "\n",
            "}"
        );

        vm.writeFile("swap_state.json", json);
        console.log(unicode"✓ Swap state saved to swap_state.json");
    }

    function _logSwapState(
        SwapState memory state
    ) internal view {
        console.log("=== Initial Swap Parameters ===");
        console.log("Secret:", vm.toString(state.secret));
        console.log("Hashlock:", vm.toString(state.hashlock));
        console.log("Order Hash:", vm.toString(state.orderHash));
        console.log("Source Amount:", state.srcAmount);
        console.log("Destination Amount:", state.dstAmount);
        console.log("Safety Deposit:", state.safetyDeposit);
        console.log("Timelock Duration:", state.timelockDuration, "seconds");
        console.log("Note: Escrow addresses will be computed in their respective fork contexts");
        console.log("");
    }

    function _printSummary(
        SwapState memory state
    ) internal view {
        console.log(unicode"=== SETUP SUMMARY ===");
        console.log(unicode"✅ Sepolia destination escrow funded:", state.dstEscrow);
        console.log(unicode"✅ Monad source escrow funded:", state.srcEscrow);
        console.log(unicode"✅ Timelock duration:", state.timelockDuration, "seconds");
        console.log(unicode"✅ Swap parameters saved to swap_state.json");
        console.log("");
        console.log("Ready for withdrawal after:", state.deploymentTime + state.timelockDuration);
    }
}
