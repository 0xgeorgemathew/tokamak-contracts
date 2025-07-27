// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { TokenMock } from "solidity-utils/contracts/mocks/TokenMock.sol";
import { Address, AddressLib } from "solidity-utils/contracts/libraries/AddressLib.sol";

import { IBaseEscrow } from "contracts/interfaces/IBaseEscrow.sol";
import { IEscrowFactory } from "contracts/interfaces/IEscrowFactory.sol";
import { Timelocks, TimelocksLib } from "contracts/libraries/TimelocksLib.sol";
import { TimelocksSettersLib } from "test/utils/libraries/TimelocksSettersLib.sol";

/**
 * @title Manual Cross-Chain Swap Script
 * @notice Comprehensive script to test cross-chain atomic swaps between Monad and Sepolia
 * @dev Run with: forge script script/ManualCrossChainSwap.s.sol --broadcast --account deployerKey
 */
contract ManualCrossChainSwap is Script {
    using TimelocksLib for Timelocks;
    using AddressLib for Address;

    // Network Configuration
    struct NetworkConfig {
        string name;
        string rpcUrl;
        address factory;
        address token;
        uint256 chainId;
        uint256 forkId;
    }

    // Swap Parameters
    struct SwapParams {
        bytes32 secret;
        bytes32 hashlock;
        bytes32 orderHash;
        uint256 deploymentTime;
        Timelocks timelocks;
        uint256 srcAmount;
        uint256 dstAmount;
        uint256 safetyDeposit;
    }

    // Track actual deployed escrow addresses
    struct EscrowAddresses {
        address dstEscrow;
        address srcEscrow;
    }

    // Network configurations
    NetworkConfig public sepolia;
    NetworkConfig public monad;

    address public deployer;

    function setUp() public {
        deployer = vm.envAddress("DEPLOYER_ADDRESS");

        // Initialize network configurations with RPC URLs from environment
        sepolia = NetworkConfig({
            name: "Sepolia",
            rpcUrl: vm.envString("SEPOLIA_RPC_URL"),
            factory: 0xf0ED16e2165537b99C47A2B90705CD381FE87472,
            token: 0xfd87f19DF4eDAAc6B6df0E2afc04e8051C98cB54,
            chainId: 11155111,
            forkId: 0 // Will be set in run()
        });

        monad = NetworkConfig({
            name: "Monad",
            rpcUrl: vm.envString("MONAD_RPC_URL"),
            factory: 0x756B01844D85010C549cEf98daBdBC73e6372804,
            token: 0xB7D3E26b95ffA0D02D9639329b56e75766cf5ba6,
            chainId: 34443,
            forkId: 0 // Will be set in run()
        });
    }

    function run() external {
        console.log("=== AUTOMATED CROSS-CHAIN SWAP: Monad -> Sepolia ===");
        console.log("Using Direct Cross-Chain Execution");
        console.log("Deployer:", deployer);
        console.log("");

        // Create forks for both networks
        console.log("Setting up network forks...");
        sepolia.forkId = vm.createFork(sepolia.rpcUrl);
        monad.forkId = vm.createFork(monad.rpcUrl);
        console.log("Network forks created");
        console.log("");

        // Generate swap parameters using Sepolia fork (for block data)
        vm.selectFork(sepolia.forkId);
        SwapParams memory params = generateSwapParams();
        logSwapParams(params);

        // Phase 1: Prepare tokens and create destination escrow on Sepolia
        console.log("=== PHASE 1: Sepolia Operations ===");
        vm.selectFork(sepolia.forkId);
        vm.startBroadcast(deployer);

        prepareTokens(params);
        address dstEscrow = createDestinationEscrow(params);

        vm.stopBroadcast();
        console.log("Sepolia phase completed");
        console.log("");

        // Phase 2: Fund source escrow on Monad
        console.log("=== PHASE 2: Monad Operations ===");
        vm.selectFork(monad.forkId);
        address srcEscrow = getSourceEscrowAddress(params);

        vm.startBroadcast(deployer);
        fundSourceEscrow(params, srcEscrow);
        vm.stopBroadcast();
        console.log("Monad phase completed");
        console.log("");

        // Phase 3: Wait for timelocks (simulation)
        console.log("=== PHASE 3: Timelock Wait ===");
        simulateTimelockWait(params);
        console.log("");

        // Phase 4: Execute withdrawals on both chains
        console.log("=== PHASE 4: Withdrawal Execution ===");
        executeWithdrawals(params, dstEscrow, srcEscrow);

        console.log("");
        console.log("CROSS-CHAIN SWAP COMPLETED SUCCESSFULLY!");
        logFinalResults(params, dstEscrow, srcEscrow);
    }

    function generateSwapParams() internal view returns (SwapParams memory) {
        // Generate deterministic values for reproducibility
        bytes32 secret = keccak256(abi.encodePacked(block.timestamp, block.prevrandao, deployer, "secret"));
        bytes32 hashlock = keccak256(abi.encode(secret));
        bytes32 orderHash = keccak256(abi.encodePacked(secret, block.timestamp, "order"));

        // Timelock configuration (in seconds from deployment)
        uint32 srcWithdrawal = 300;         // 5 minutes
        uint32 srcPublicWithdrawal = 600;   // 10 minutes
        uint32 srcCancellation = 1800;      // 30 minutes
        uint32 srcPublicCancellation = 3600; // 60 minutes
        uint32 dstWithdrawal = 300;         // 5 minutes
        uint32 dstPublicWithdrawal = 600;   // 10 minutes
        uint32 dstCancellation = 900;       // 15 minutes

        // Encode timelocks properly (without deployedAt - contract sets it)
        Timelocks timelocks = TimelocksSettersLib.init(
            srcWithdrawal,
            srcPublicWithdrawal,
            srcCancellation,
            srcPublicCancellation,
            dstWithdrawal,
            dstPublicWithdrawal,
            dstCancellation,
            0 // deployedAt = 0, contract will set this
        );

        return SwapParams({
            secret: secret,
            hashlock: hashlock,
            orderHash: orderHash,
            deploymentTime: block.timestamp,
            timelocks: timelocks,
            srcAmount: 2 ether,      // 2 tokens on Monad
            dstAmount: 1 ether,      // 1 token on Sepolia
            safetyDeposit: 0.1 ether // 0.1 ETH safety deposit
        });
    }

    function prepareTokens(SwapParams memory params) internal {
        console.log("Preparing tokens on Sepolia...");
        TokenMock sepoliaToken = TokenMock(sepolia.token);

        // Mint tokens
        sepoliaToken.mint(deployer, 10 ether);
        console.log("  Minted 10 tokens");

        // Approve tokens for escrow factory
        sepoliaToken.approve(sepolia.factory, params.dstAmount);
        console.log("  Approved tokens for escrow factory");

        // Verify balance
        uint256 balance = sepoliaToken.balanceOf(deployer);
        console.log("  Current balance:");
        console.log(balance);
    }

    function createDestinationEscrow(SwapParams memory params) internal returns (address) {
        console.log("Creating destination escrow on Sepolia...");

        IBaseEscrow.Immutables memory dstImmutables = IBaseEscrow.Immutables({
            orderHash: params.orderHash,
            hashlock: params.hashlock,
            maker: Address.wrap(uint160(deployer)),
            taker: Address.wrap(uint160(deployer)),
            token: Address.wrap(uint160(sepolia.token)),
            amount: params.dstAmount,
            safetyDeposit: params.safetyDeposit,
            timelocks: params.timelocks
        });

        uint256 srcCancellationTimestamp = params.deploymentTime + 1800; // 30 minutes

        // Create destination escrow
        IEscrowFactory sepoliaFactory = IEscrowFactory(sepolia.factory);

        // Get the pre-computed address
        address expectedDstEscrow = sepoliaFactory.addressOfEscrowDst(dstImmutables);
        console.log("  Expected escrow address:");
        console.log(expectedDstEscrow);

        sepoliaFactory.createDstEscrow{value: params.safetyDeposit}(
            dstImmutables,
            srcCancellationTimestamp
        );

        console.log("  Destination escrow created");
        console.log("  Safety deposit sent");

        return expectedDstEscrow;
    }

    function getSourceEscrowAddress(SwapParams memory params) internal view returns (address) {
        console.log("Computing source escrow address on Monad...");

        IBaseEscrow.Immutables memory srcImmutables = IBaseEscrow.Immutables({
            orderHash: params.orderHash,
            hashlock: params.hashlock,
            maker: Address.wrap(uint160(deployer)),
            taker: Address.wrap(uint160(deployer)),
            token: Address.wrap(uint160(monad.token)),
            amount: params.srcAmount,
            safetyDeposit: params.safetyDeposit,
            timelocks: params.timelocks
        });

        IEscrowFactory monadFactory = IEscrowFactory(monad.factory);
        address srcEscrow = monadFactory.addressOfEscrowSrc(srcImmutables);
        console.log("  Source escrow address:");
        console.log(srcEscrow);

        return srcEscrow;
    }

    function fundSourceEscrow(SwapParams memory params, address srcEscrow) internal {
        console.log("Funding source escrow on Monad...");

        // Transfer tokens to source escrow
        IERC20 monadToken = IERC20(monad.token);
        monadToken.transfer(srcEscrow, params.srcAmount);
        console.log("  Transferred tokens to escrow");

        // Send safety deposit
        (bool success,) = srcEscrow.call{value: params.safetyDeposit}("");
        require(success, "Failed to send safety deposit");
        console.log("  Sent safety deposit");

        // Verify funding
        uint256 tokenBalance = monadToken.balanceOf(srcEscrow);
        uint256 ethBalance = srcEscrow.balance;
        console.log("  Escrow token balance:");
        console.log(tokenBalance);
        console.log("  Escrow ETH balance:");
        console.log(ethBalance);
    }

    function simulateTimelockWait(SwapParams memory params) internal {
        uint256 withdrawalTime = params.deploymentTime + 300; // 5 minutes
        uint256 currentTime = block.timestamp;

        if (currentTime < withdrawalTime) {
            uint256 waitTime = withdrawalTime - currentTime;
            console.log("Timelock period: need to wait");
            console.log(waitTime);
            console.log("seconds");
            console.log("  Current time:");
            console.log(currentTime);
            console.log("  Withdrawal time:");
            console.log(withdrawalTime);

            // In a real scenario, you'd wait or use a separate script
            // For testing, we'll advance time
            console.log("  Advancing time for testing...");
            vm.warp(withdrawalTime + 1);
            console.log("  Time advanced to enable withdrawals");
        } else {
            console.log("Timelock period already passed");
        }
    }

    function executeWithdrawals(
        SwapParams memory params,
        address dstEscrow,
        address srcEscrow
    ) internal {
        // Update timelocks with actual deployment time for withdrawal validation
        uint256 actualDeploymentTime = params.deploymentTime;

        // Prepare immutables with correct deployment time
        IBaseEscrow.Immutables memory dstImmutables = IBaseEscrow.Immutables({
            orderHash: params.orderHash,
            hashlock: params.hashlock,
            maker: Address.wrap(uint160(deployer)),
            taker: Address.wrap(uint160(deployer)),
            token: Address.wrap(uint160(sepolia.token)),
            amount: params.dstAmount,
            safetyDeposit: params.safetyDeposit,
            timelocks: params.timelocks.setDeployedAt(actualDeploymentTime)
        });

        IBaseEscrow.Immutables memory srcImmutables = IBaseEscrow.Immutables({
            orderHash: params.orderHash,
            hashlock: params.hashlock,
            maker: Address.wrap(uint160(deployer)),
            taker: Address.wrap(uint160(deployer)),
            token: Address.wrap(uint160(monad.token)),
            amount: params.srcAmount,
            safetyDeposit: params.safetyDeposit,
            timelocks: params.timelocks.setDeployedAt(actualDeploymentTime)
        });

        // Execute destination withdrawal (Sepolia) - reveals secret
        console.log("Executing destination withdrawal (Sepolia)...");
        vm.selectFork(sepolia.forkId);
        vm.startBroadcast(deployer);

        try IBaseEscrow(dstEscrow).withdraw(params.secret, dstImmutables) {
            console.log("  Secret revealed and tokens withdrawn");
        } catch {
            console.log("  Withdrawal failed - checking escrow state");

            // Debug: check escrow balance
            uint256 escrowBalance = IERC20(sepolia.token).balanceOf(dstEscrow);
            console.log("  Escrow token balance:");
            console.log(escrowBalance);

            uint256 escrowEthBalance = dstEscrow.balance;
            console.log("  Escrow ETH balance:");
            console.log(escrowEthBalance);

            // Try to get better error info
            revert("Destination withdrawal failed");
        }

        vm.stopBroadcast();

        // Execute source withdrawal (Monad) - completes swap
        console.log("Executing source withdrawal (Monad)...");
        vm.selectFork(monad.forkId);
        vm.startBroadcast(deployer);

        try IBaseEscrow(srcEscrow).withdraw(params.secret, srcImmutables) {
            console.log("  Source tokens withdrawn using revealed secret");
        } catch {
            console.log("  Source withdrawal failed");
            revert("Source withdrawal failed");
        }

        vm.stopBroadcast();
    }

    function logSwapParams(SwapParams memory params) internal view {
        console.log("=== Swap Parameters ===");
        console.log("Secret:");
        console.log(vm.toString(params.secret));
        console.log("Hashlock:");
        console.log(vm.toString(params.hashlock));
        console.log("Order Hash:");
        console.log(vm.toString(params.orderHash));
        console.log("Deployment Time:");
        console.log(params.deploymentTime);
        console.log("Source Amount:");
        console.log(params.srcAmount);
        console.log("Destination Amount:");
        console.log(params.dstAmount);
        console.log("Safety Deposit:");
        console.log(params.safetyDeposit);
        console.log("");
    }

    function logFinalResults(
        SwapParams memory params,
        address dstEscrow,
        address srcEscrow
    ) internal view {
        console.log("=== Final Results ===");
        console.log("Cross-chain atomic swap completed");
        console.log("Secret properly revealed and used");
        console.log("Both escrows emptied successfully");
        console.log("Safety deposits recovered");
        console.log("");
        console.log("Swap Details:");
        console.log("  Secret:");
        console.log(vm.toString(params.secret));
        console.log("  Hashlock:");
        console.log(vm.toString(params.hashlock));
        console.log("  Destination escrow:");
        console.log(dstEscrow);
        console.log("  Source escrow:");
        console.log(srcEscrow);
        console.log("");
        console.log("Networks:");
        console.log("  Sepolia Factory:");
        console.log(sepolia.factory);
        console.log("  Monad Factory:");
        console.log(monad.factory);
    }

    // Utility function for debugging timelock details
    function getTimelockDetails(Timelocks timelocks, uint256 deployedAt) external pure returns (
        uint256 srcWithdrawal,
        uint256 srcPublicWithdrawal,
        uint256 srcCancellation,
        uint256 srcPublicCancellation,
        uint256 dstWithdrawal,
        uint256 dstPublicWithdrawal,
        uint256 dstCancellation
    ) {
        Timelocks withDeployedAt = timelocks.setDeployedAt(deployedAt);

        return (
            withDeployedAt.get(TimelocksLib.Stage.SrcWithdrawal),
            withDeployedAt.get(TimelocksLib.Stage.SrcPublicWithdrawal),
            withDeployedAt.get(TimelocksLib.Stage.SrcCancellation),
            withDeployedAt.get(TimelocksLib.Stage.SrcPublicCancellation),
            withDeployedAt.get(TimelocksLib.Stage.DstWithdrawal),
            withDeployedAt.get(TimelocksLib.Stage.DstPublicWithdrawal),
            withDeployedAt.get(TimelocksLib.Stage.DstCancellation)
        );
    }
}
