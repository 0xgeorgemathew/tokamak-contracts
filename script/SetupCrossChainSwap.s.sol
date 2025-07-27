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
    uint32 constant TESTNET_TIMELOCK = 60; // 60 seconds for testing
    address public deployer;

    function setUp() public {
        deployer = vm.envAddress("DEPLOYER_ADDRESS");
        console.log("=== CROSS-CHAIN SWAP SETUP ===");
        console.log("Deployer:", deployer);
        console.log("Timelock Duration:", TESTNET_TIMELOCK);
        console.log("Duration unit: seconds");
        console.log("");
    }

    function run() external {
        // Load network configurations
        (DeploymentData memory sepoliaData, DeploymentData memory monadData) = loadDeploymentConfig();

        // Generate swap parameters
        SwapState memory state = generateSwapState(sepoliaData, monadData);
        logSwapState(state);

        // Phase 1: Setup Sepolia destination escrow
        console.log("=== PHASE 1: Sepolia Destination Escrow ===");
        vm.createSelectFork(vm.envString("SEPOLIA_RPC_URL"));
        setupSepoliaEscrow(state);

        // Phase 2: Setup Monad source escrow
        console.log("=== PHASE 2: Monad Source Escrow ===");
        vm.createSelectFork(vm.envString("MONAD_RPC_URL"));
        setupMonadEscrow(state);

        // Save state for subsequent scripts
        console.log("=== SAVING SWAP STATE ===");
        saveSwapState(state);

        console.log("=== SETUP COMPLETED ===");
        console.log("Next steps:");
        console.log("1. Wait 60+ seconds for timelock");
        console.log("2. Run: forge script script/2_CheckSwapStatus.s.sol");
        console.log("3. Run: forge script script/3_ExecuteWithdrawals.s.sol --broadcast");
        console.log("");
        printSummary(state);
    }

    function loadDeploymentConfig() internal view returns (DeploymentData memory sepoliaData, DeploymentData memory monadData) {
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

    function generateSwapState(
        DeploymentData memory sepoliaData,
        DeploymentData memory monadData
    ) internal view returns (SwapState memory) {
        // Generate deterministic parameters
        uint256 currentTime = block.timestamp;
        bytes32 secret = keccak256(abi.encodePacked(currentTime, deployer, "testnet_v1"));
        bytes32 hashlock = keccak256(abi.encode(secret));
        bytes32 orderHash = keccak256(abi.encodePacked(secret, currentTime, "order_v1"));

        // Create timelocks for escrow address computation
        Timelocks timelocks = TimelocksSettersLib.init(
            TESTNET_TIMELOCK,     // srcWithdrawal: 60s
            TESTNET_TIMELOCK * 2, // srcPublicWithdrawal: 120s
            TESTNET_TIMELOCK * 3, // srcCancellation: 180s
            TESTNET_TIMELOCK * 4, // srcPublicCancellation: 240s
            TESTNET_TIMELOCK,     // dstWithdrawal: 60s
            TESTNET_TIMELOCK * 2, // dstPublicWithdrawal: 120s
            TESTNET_TIMELOCK * 2, // dstCancellation: 120s
            0 // deployedAt = 0
        );

        // Compute escrow addresses
        uint256 srcAmount = 1 ether;
        uint256 dstAmount = 0.5 ether;
        uint256 safetyDeposit = 0.01 ether;

        IBaseEscrow.Immutables memory dstImmutables = IBaseEscrow.Immutables({
            orderHash: orderHash,
            hashlock: hashlock,
            maker: Address.wrap(uint160(deployer)),
            taker: Address.wrap(uint160(deployer)),
            token: Address.wrap(uint160(sepoliaData.swapToken)),
            amount: dstAmount,
            safetyDeposit: safetyDeposit,
            timelocks: timelocks
        });

        IBaseEscrow.Immutables memory srcImmutables = IBaseEscrow.Immutables({
            orderHash: orderHash,
            hashlock: hashlock,
            maker: Address.wrap(uint160(deployer)),
            taker: Address.wrap(uint160(deployer)),
            token: Address.wrap(uint160(monadData.swapToken)),
            amount: srcAmount,
            safetyDeposit: safetyDeposit,
            timelocks: timelocks
        });

        console.log("Computing escrow addresses...");
        console.log("Sepolia factory:", sepoliaData.escrowFactory);
        console.log("Monad factory:", monadData.escrowFactory);
        
        address dstEscrow;
        address srcEscrow;
        
        try IEscrowFactory(sepoliaData.escrowFactory).addressOfEscrowDst(dstImmutables) returns (address addr) {
            dstEscrow = addr;
            console.log("Destination escrow computed:", dstEscrow);
        } catch {
            console.log("ERROR: Failed to compute destination escrow address");
            revert("Destination escrow computation failed");
        }
        
        try IEscrowFactory(monadData.escrowFactory).addressOfEscrowSrc(srcImmutables) returns (address addr) {
            srcEscrow = addr;
            console.log("Source escrow computed:", srcEscrow);
        } catch {
            console.log("ERROR: Failed to compute source escrow address");
            revert("Source escrow computation failed");
        }

        return SwapState({
            secret: secret,
            hashlock: hashlock,
            orderHash: orderHash,
            deploymentTime: currentTime,
            srcAmount: srcAmount,
            dstAmount: dstAmount,
            safetyDeposit: safetyDeposit,
            dstEscrow: dstEscrow,
            srcEscrow: srcEscrow,
            sepoliaFactory: sepoliaData.escrowFactory,
            sepoliaToken: sepoliaData.swapToken,
            monadFactory: monadData.escrowFactory,
            monadToken: monadData.swapToken,
            timelockDuration: TESTNET_TIMELOCK
        });
    }

    function setupSepoliaEscrow(SwapState memory state) internal {
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

        Timelocks timelocks = TimelocksSettersLib.init(
            state.timelockDuration,     // srcWithdrawal
            state.timelockDuration * 2, // srcPublicWithdrawal
            state.timelockDuration * 3, // srcCancellation
            state.timelockDuration * 4, // srcPublicCancellation
            state.timelockDuration,     // dstWithdrawal
            state.timelockDuration * 2, // dstPublicWithdrawal
            state.timelockDuration * 2, // dstCancellation
            0 // deployedAt
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

        uint256 srcCancellationTimestamp = block.timestamp + state.timelockDuration * 3;

        IEscrowFactory(state.sepoliaFactory).createDstEscrow{value: state.safetyDeposit}(
            dstImmutables,
            srcCancellationTimestamp
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

    function setupMonadEscrow(SwapState memory state) internal {
        vm.startBroadcast(deployer);

        // Setup tokens
        console.log("Setting up Monad tokens...");
        TokenMock monadToken = TokenMock(state.monadToken);
        monadToken.mint(deployer, 10 ether);
        console.log(unicode"  ✓ Minted 10 tokens");

        // Fund source escrow
        console.log("Funding source escrow...");
        monadToken.transfer(state.srcEscrow, state.srcAmount);
        (bool success,) = state.srcEscrow.call{value: state.safetyDeposit}("");
        require(success, "Failed to send safety deposit");

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

    function saveSwapState(SwapState memory state) internal {
        string memory json = string.concat(
            '{\n',
            '  "secret": "', vm.toString(state.secret), '",\n',
            '  "hashlock": "', vm.toString(state.hashlock), '",\n',
            '  "orderHash": "', vm.toString(state.orderHash), '",\n',
            '  "deploymentTime": ', vm.toString(state.deploymentTime), ',\n',
            '  "srcAmount": "', vm.toString(state.srcAmount), '",\n',
            '  "dstAmount": "', vm.toString(state.dstAmount), '",\n',
            '  "safetyDeposit": "', vm.toString(state.safetyDeposit), '",\n',
            '  "dstEscrow": "', vm.toString(state.dstEscrow), '",\n',
            '  "srcEscrow": "', vm.toString(state.srcEscrow), '",\n',
            '  "sepoliaFactory": "', vm.toString(state.sepoliaFactory), '",\n',
            '  "sepoliaToken": "', vm.toString(state.sepoliaToken), '",\n',
            '  "monadFactory": "', vm.toString(state.monadFactory), '",\n',
            '  "monadToken": "', vm.toString(state.monadToken), '",\n',
            '  "timelockDuration": ', vm.toString(state.timelockDuration), '\n',
            '}'
        );

        vm.writeFile("swap_state.json", json);
        console.log(unicode"✓ Swap state saved to swap_state.json");
    }

    function logSwapState(SwapState memory state) internal view {
        console.log("=== Generated Swap Parameters ===");
        console.log("Secret:", vm.toString(state.secret));
        console.log("Hashlock:", vm.toString(state.hashlock));
        console.log("Order Hash:", vm.toString(state.orderHash));
        console.log("Source Amount:", state.srcAmount);
        console.log("Destination Amount:", state.dstAmount);
        console.log("Safety Deposit:", state.safetyDeposit);
        console.log("Destination Escrow:", state.dstEscrow);
        console.log("Source Escrow:", state.srcEscrow);
        console.log("");
    }

    function printSummary(SwapState memory state) internal view {
        console.log(unicode"=== SETUP SUMMARY ===");
        console.log(unicode"✅ Sepolia destination escrow funded:", state.dstEscrow);
        console.log(unicode"✅ Monad source escrow funded:", state.srcEscrow);
        console.log(unicode"✅ Timelock duration:", state.timelockDuration, "seconds");
        console.log(unicode"✅ Swap parameters saved to swap_state.json");
        console.log("");
        console.log("Ready for withdrawal after:", state.deploymentTime + state.timelockDuration);
    }
}
