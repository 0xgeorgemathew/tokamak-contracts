// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

import { Script } from "forge-std/Script.sol";

import { IOrderMixin } from "limit-order-protocol/contracts/interfaces/IOrderMixin.sol";
import { TakerTraits } from "limit-order-protocol/contracts/libraries/TakerTraitsLib.sol";
import { MakerTraits } from "limit-order-protocol/contracts/libraries/MakerTraitsLib.sol";

import { TokenCustomDecimalsMock } from "solidity-utils/contracts/mocks/TokenCustomDecimalsMock.sol";
import { Address } from "solidity-utils/contracts/libraries/AddressLib.sol";

import { Timelocks, TimelocksLib } from "contracts/libraries/TimelocksLib.sol";
import { BaseEscrowFactory } from "contracts/BaseEscrowFactory.sol";
import { ResolverExample } from "contracts/mocks/ResolverExample.sol";
import { IResolverExample } from "contracts/interfaces/IResolverExample.sol";
import { IEscrowFactory } from "contracts/interfaces/IEscrowFactory.sol";
import { IBaseEscrow } from "contracts/interfaces/IBaseEscrow.sol";
import { EscrowSrc } from "contracts/EscrowSrc.sol";

import { CrossChainTestLib } from "test/utils/libraries/CrossChainTestLib.sol";
import { TimelocksSettersLib } from "test/utils/libraries/TimelocksSettersLib.sol";

import { Config, ConfigLib, DeploymentConfig } from "./utils/ConfigLib.sol";
import { EscrowDevOpsTools } from "./utils/EscrowDevOpsTools.sol";

// solhint-disable no-console
import { console } from "forge-std/console.sol";
import { stdJson } from "forge-std/StdJson.sol";
// solhint-disable no-console
//solhint-disable-next-line no-empty-block

contract CreateOrder is Script {
    using stdJson for string;

    error NativeTokenTransferFailure();
    error InvalidMode();

    enum Mode {
        cancel,
        withdraw
    }

    mapping(uint256 => address) public FEE_TOKEN; // solhint-disable-line var-name-mixedcase
    BaseEscrowFactory internal _escrowFactory;
    address internal _deployerAddress;
    address internal _makerAddress;

    function _getScaledAmount(uint256 rawAmount, address token) internal view returns (uint256) {
        if (token == address(0)) {
            return rawAmount; // Native token, no scaling needed
        }
        
        uint8 decimals = ERC20(token).decimals();
        return rawAmount * (10 ** decimals);
    }

    function run() external {
        _defineFeeTokens();

        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/examples/config/config.json");

        Config memory config = ConfigLib.getConfig(vm, path);
        DeploymentConfig memory deploymentConfig = ConfigLib.getDeploymentConfig(vm, block.chainid);

        _escrowFactory = BaseEscrowFactory(deploymentConfig.escrowFactory);

        _deployerAddress = vm.envAddress("DEPLOYER_ADDRESS"); // deployerKey
        _makerAddress = vm.envAddress("MAKER_ADDRESS"); // bravoKey

        string memory mode = vm.envString("MODE");

        if (keccak256(bytes(mode)) == keccak256("deployMocks")) {
            _deployResolverExample(deploymentConfig);
            _replaceTokensForMocks(config);
        } else if (keccak256(bytes(mode)) == keccak256("deployEscrowSrc")) {
            _deployEscrowSrc(config, deploymentConfig);
        } else if (keccak256(bytes(mode)) == keccak256("deployEscrowDst")) {
            _deployEscrowDst(config, deploymentConfig);
        } else if (keccak256(bytes(mode)) == keccak256("withdrawSrc")) {
            _callResolverForSrc(config, deploymentConfig, Mode.withdraw);
        } else if (keccak256(bytes(mode)) == keccak256("withdrawDst")) {
            _callResolverForDst(config, deploymentConfig, Mode.withdraw);
        } else if (keccak256(bytes(mode)) == keccak256("cancelSrc")) {
            _callResolverForSrc(config, deploymentConfig, Mode.cancel);
        } else if (keccak256(bytes(mode)) == keccak256("cancelDst")) {
            _callResolverForDst(config, deploymentConfig, Mode.cancel);
        }
    }

    function _deployEscrowSrc(
        Config memory config,
        DeploymentConfig memory deploymentConfig
    ) internal {
        // Load secret data from Step 1 & 2
        string memory secretsPath = "./data/swap-secrets.json";
        string memory secretsJson = vm.readFile(secretsPath);

        bytes32 secret = bytes32(secretsJson.readBytes(".secret"));
        bytes32 hashlock = bytes32(secretsJson.readBytes(".secretHash"));

        // Use deployment config addresses
        address srcToken = deploymentConfig.swapToken;
        address resolver = deploymentConfig.resolver;
        address dstToken = ConfigLib.getCrossChainTokenAddress(vm, block.chainid);

        console.log("Src token: %s", srcToken);
        console.log("Dst token: %s", dstToken);
        console.log("Resolver: %s", resolver);

        CrossChainTestLib.SrcTimelocks memory srcTimelocks = CrossChainTestLib.SrcTimelocks({
            withdrawal: config.withdrawalSrcTimelock, // finality lock
            publicWithdrawal: config.publicWithdrawalSrcTimelock, // for private withdrawal
            cancellation: config.cancellationSrcTimelock, // for public withdrawal
            publicCancellation: config.publicCancellationSrcTimelock // for private cancellation
         });

        CrossChainTestLib.DstTimelocks memory dstTimelocks = CrossChainTestLib.DstTimelocks({
            withdrawal: config.withdrawalDstTimelock, // finality lock
            publicWithdrawal: config.publicWithdrawalDstTimelock, // for private withdrawal
            cancellation: config.cancellationDstTimelock // for public withdrawal
         });

        Timelocks timelocks = TimelocksSettersLib.init(
            srcTimelocks.withdrawal,
            srcTimelocks.publicWithdrawal,
            srcTimelocks.cancellation,
            srcTimelocks.publicCancellation,
            dstTimelocks.withdrawal,
            dstTimelocks.publicWithdrawal,
            dstTimelocks.cancellation,
            0
        );

        address[] memory resolvers = new address[](1);
        resolvers[0] = resolver;

        address maker = _makerAddress; // Use bravoKey address

        // Use the pre-signed order from Step 1 instead of generating a new one
        IOrderMixin.Order memory order = IOrderMixin.Order({
            salt: secretsJson.readUint(".signatureData.order.salt"),
            maker: Address.wrap(uint160(secretsJson.readAddress(".signatureData.order.maker"))),
            receiver: Address.wrap(uint160(secretsJson.readAddress(".signatureData.order.receiver"))),
            makerAsset: Address.wrap(uint160(secretsJson.readAddress(".signatureData.order.makerAsset"))),
            takerAsset: Address.wrap(uint160(secretsJson.readAddress(".signatureData.order.takerAsset"))),
            makingAmount: secretsJson.readUint(".signatureData.order.makingAmount"),
            takingAmount: secretsJson.readUint(".signatureData.order.takingAmount"),
            makerTraits: MakerTraits.wrap(secretsJson.readUint(".signatureData.order.makerTraits"))
        });

         bytes32 orderHash = IOrderMixin(deploymentConfig.limitOrderProtocol).hashOrder(order);

        uint256 scaledSrcAmount = _getScaledAmount(config.srcAmount, srcToken);
        
        IBaseEscrow.Immutables memory immutables = IBaseEscrow.Immutables({
            orderHash: orderHash,
            amount: scaledSrcAmount,
            maker: Address.wrap(uint160(maker)),
            taker: Address.wrap(uint160(resolver)),
            token: Address.wrap(uint160(srcToken)),
            hashlock: hashlock,
            safetyDeposit: config.safetyDeposit,
            timelocks: timelocks
        });

        // Build ExtraDataArgs for factory callback - this needs to match BaseEscrowFactory expectations
        uint256 destinationChainId = block.chainid == 11155111 ? 10143 : 11155111; // Opposite chain
        address destinationToken = block.chainid == 11155111 ? 
            0x3A84567b87a039FFD5043949E0Ae119617746539 : // Monad token
            0x085619Cef93E5A6Cff7683558418424748880663;   // Sepolia token
            
        console.log("Building ExtraDataArgs:");
        console.log("  hashlockInfo:", vm.toString(hashlock));
        console.log("  dstChainId:", destinationChainId);
        console.log("  dstToken:", destinationToken);
        console.log("  srcSafetyDeposit:", config.safetyDeposit);
        console.log("  dstSafetyDeposit:", config.safetyDeposit);
        console.log("  deposits (packed):", (uint256(config.safetyDeposit) << 128) | config.safetyDeposit);
        
        // Create extraData exactly as CrossChainTestLib does for consistency
        bytes memory extraDataArgs = abi.encode(
            hashlock,                    // hashlockInfo
            destinationChainId,         // dstChainId  
            destinationToken,           // dstToken (raw address, not Address type)
            (uint256(config.safetyDeposit) << 128) | config.safetyDeposit, // deposits: src << 128 | dst
            timelocks                   // timelocks
        );
        
        console.log("ExtraDataArgs encoded length:", extraDataArgs.length);
        console.logBytes(extraDataArgs);

        // The extraData structure needs: resolverValidation + ExtraDataArgs(160 bytes)
        // For simplicity, we'll create minimal resolver validation data
        bytes memory resolverValidationData = abi.encodePacked(
            uint32(0), // resolver fee
            uint32(block.timestamp), // auction start time  
            uint80(uint160(resolver)), // resolver address
            uint16(0), // time delta
            bytes1(0x08) | bytes1(0x00) // whitelist length = 1, no resolver fee
        );
        
        // Combine resolver validation + ExtraDataArgs (which should be exactly 160 bytes)
        bytes memory fullExtraData = abi.encodePacked(resolverValidationData, extraDataArgs);
        
        console.log("Resolver validation data length:", resolverValidationData.length);
        console.log("ExtraDataArgs length:", extraDataArgs.length);
        console.log("Full extraData length:", fullExtraData.length);

        CrossChainTestLib.SwapData memory swapData = CrossChainTestLib.SwapData({
            order: order,
            orderHash: orderHash,
            immutables: immutables,
            srcClone: EscrowSrc(BaseEscrowFactory(deploymentConfig.escrowFactory).addressOfEscrowSrc(immutables)),
            extension: "",
            extraData: fullExtraData
        });

        // Load signature data from Step 1 (off-chain signature)
        bytes32 r = bytes32(secretsJson.readBytes(".signatureData.r"));
        bytes32 vs = bytes32(secretsJson.readBytes(".signatureData.vs"));

        console.log("Using pre-signed order from Step 1");
        console.log("Signature r:", vm.toString(r));
        console.log("Signature vs:", vm.toString(vs));

        (TakerTraits takerTraits, bytes memory args) = CrossChainTestLib.buildTakerTraits(
            true, // makingAmount
            false, // unwrapWeth
            true, // skipMakerPermit
            false, // usePermit2
            address(swapData.srcClone), // target - the computed escrow address
            "", // extension - empty for now
            fullExtraData, // interaction - contains resolver validation + ExtraDataArgs for factory
            0 // threshold
        );

        _mintToken(srcToken, maker, scaledSrcAmount);
        
        // Verify token approval was completed in Step 2
        _verifyTokenApproval(srcToken, maker, deploymentConfig.limitOrderProtocol, scaledSrcAmount);
        
        // Fund resolver with source tokens for limit order completion
        _fundResolver(srcToken, resolver, scaledSrcAmount);
        
        // Approve resolver tokens to Limit Order Protocol
        _approveResolverTokens(srcToken, resolver, deploymentConfig.limitOrderProtocol, scaledSrcAmount);
        
        _sendNativeToken(resolver, config.safetyDeposit);

        vm.startBroadcast(_deployerAddress);
        // Pass the full takingAmount to ensure proper token transfer to escrow
        IResolverExample(resolver).deploySrc(
            swapData.immutables, swapData.order, r, vs, order.takingAmount, takerTraits, args
        );
        vm.stopBroadcast();
    }

    function _deployEscrowDst(
        Config memory config,
        DeploymentConfig memory deploymentConfig
    ) internal {
        // Load secret data from Step 1 & 2
        string memory secretsPath = "./data/swap-secrets.json";
        string memory secretsJson = vm.readFile(secretsPath);

        bytes32 secret = bytes32(secretsJson.readBytes(".secret"));
        bytes32 hashlock = bytes32(secretsJson.readBytes(".secretHash"));

        // Use deployment config addresses
        address dstToken = deploymentConfig.swapToken;
        address resolver = deploymentConfig.resolver;
        address srcToken = ConfigLib.getCrossChainTokenAddress(vm, block.chainid);

        (bytes32 orderHash, Timelocks timelocks) =
            EscrowDevOpsTools.getOrderHashAndTimelocksFromSrcEscrowCreatedEvent(config);

        console.log("Src token: %s", srcToken);
        console.log("Dst token: %s", dstToken);
        console.log("Resolver: %s", resolver);
        console.logBytes32(orderHash);
        console.log(Timelocks.unwrap(timelocks));

        uint256 scaledDstAmount = _getScaledAmount(config.dstAmount, dstToken);

        IBaseEscrow.Immutables memory escrowImmutables = CrossChainTestLib.buildDstEscrowImmutables(
            orderHash, hashlock, scaledDstAmount, config.maker, resolver, dstToken, config.safetyDeposit, timelocks
        );

        uint256 srcCancellationTimestamp = type(uint32).max;

        _mintToken(dstToken, resolver, scaledDstAmount);
        _sendNativeToken(resolver, config.safetyDeposit);

        uint256 safetyDeposit = config.safetyDeposit;
        if (dstToken == address(0)) {
            safetyDeposit += scaledDstAmount; // add safety deposit to the amount if native token
        } else {
            address[] memory targets = new address[](1);
            bytes[] memory arguments = new bytes[](1);
            targets[0] = dstToken;
            arguments[0] =
                abi.encodePacked(IERC20(dstToken).approve.selector, abi.encode(deploymentConfig.escrowFactory, scaledDstAmount));

            vm.startBroadcast(_deployerAddress);
            IResolverExample(resolver).arbitraryCalls(targets, arguments);
            vm.stopBroadcast();
        }

        vm.startBroadcast(_deployerAddress);
        IResolverExample(resolver).deployDst{ value: safetyDeposit }(escrowImmutables, srcCancellationTimestamp);
        vm.stopBroadcast();
    }

    function _callResolverForDst(Config memory config, DeploymentConfig memory deploymentConfig, Mode mode) internal {
        // Load secret data from Step 1 & 2
        string memory secretsPath = "./data/swap-secrets.json";
        string memory secretsJson = vm.readFile(secretsPath);

        bytes32 secret = bytes32(secretsJson.readBytes(".secret"));
        bytes32 hashlock = bytes32(secretsJson.readBytes(".secretHash"));

        // Use deployment config addresses
        address dstToken = deploymentConfig.swapToken;
        address resolver = deploymentConfig.resolver;

        (bytes32 orderHash, Timelocks timelocks) =
            EscrowDevOpsTools.getOrderHashAndTimelocksFromSrcEscrowCreatedEvent(config);
        (address escrow, uint256 deployedAt) =
            EscrowDevOpsTools.getEscrowDstAddressAndDeployTimeFromDstEscrowCreatedEvent(deploymentConfig.escrowFactory);

        timelocks = TimelocksLib.setDeployedAt(timelocks, deployedAt);

        uint256 scaledDstAmount = _getScaledAmount(config.dstAmount, dstToken);

        IBaseEscrow.Immutables memory immutables = IBaseEscrow.Immutables({
            orderHash: orderHash,
            amount: scaledDstAmount,
            maker: Address.wrap(uint160(config.maker)),
            taker: Address.wrap(uint160(resolver)),
            token: Address.wrap(uint160(dstToken)),
            hashlock: hashlock,
            safetyDeposit: config.safetyDeposit,
            timelocks: timelocks
        });

        address[] memory targets = new address[](1);
        bytes[] memory data = new bytes[](1);
        targets[0] = escrow;

        if (mode == Mode.cancel) {
            data[0] = abi.encodeWithSelector(IBaseEscrow(escrow).cancel.selector, immutables);
        } else if (mode == Mode.withdraw) {
            data[0] = abi.encodeWithSelector(IBaseEscrow(escrow).withdraw.selector, secret, immutables);
        } else {
            revert InvalidMode();
        }

        vm.startBroadcast(_deployerAddress);
        IResolverExample(resolver).arbitraryCalls(targets, data);
        vm.stopBroadcast();
    }

    function _callResolverForSrc(Config memory config, DeploymentConfig memory deploymentConfig, Mode mode) internal {
        // Load secret data from Step 1 & 2
        string memory secretsPath = "./data/swap-secrets.json";
        string memory secretsJson = vm.readFile(secretsPath);

        bytes32 secret = bytes32(secretsJson.readBytes(".secret"));
        bytes32 hashlock = bytes32(secretsJson.readBytes(".secretHash"));

        // Use deployment config addresses
        address srcToken = deploymentConfig.swapToken;
        address resolver = deploymentConfig.resolver;

        (bytes32 orderHash, Timelocks timelocks) =
            EscrowDevOpsTools.getOrderHashAndTimelocksFromSrcEscrowCreatedEvent(config);

        uint256 scaledSrcAmount = _getScaledAmount(config.srcAmount, srcToken);

        IBaseEscrow.Immutables memory immutables = IBaseEscrow.Immutables({
            orderHash: orderHash,
            amount: scaledSrcAmount,
            maker: Address.wrap(uint160(config.maker)),
            taker: Address.wrap(uint160(resolver)),
            token: Address.wrap(uint160(srcToken)),
            hashlock: hashlock,
            safetyDeposit: config.safetyDeposit,
            timelocks: timelocks
        });

        address escrow = IEscrowFactory(_escrowFactory).addressOfEscrowSrc(immutables);

        address[] memory targets = new address[](1);
        bytes[] memory data = new bytes[](1);
        targets[0] = escrow;

        if (mode == Mode.cancel) {
            data[0] = abi.encodeWithSelector(IBaseEscrow(escrow).cancel.selector, immutables);
        } else if (mode == Mode.withdraw) {
            data[0] = abi.encodeWithSelector(IBaseEscrow(escrow).withdraw.selector, secret, immutables);
        } else {
            revert InvalidMode();
        }

        vm.startBroadcast(_deployerAddress);
        IResolverExample(resolver).arbitraryCalls(targets, data);
        vm.stopBroadcast();
    }

    function _sendNativeToken(address to, uint256 amount) internal {
        vm.startBroadcast(_deployerAddress);
        (bool success,) = to.call{ value: amount }("");
        if (!success) {
            revert NativeTokenTransferFailure();
        }
        vm.stopBroadcast();
    }

    function _approveTokens(uint256 pk, address token, address to, uint256 amount) internal {
        if (token == address(0) || amount == 0) {
            return;
        }

        vm.startBroadcast(pk);
        IERC20(token).approve(to, amount);
        vm.stopBroadcast();
    }

    function _verifyTokenApproval(address token, address owner, address spender, uint256 requiredAmount) internal view {
        if (token == address(0)) {
            return; // No approval needed for native tokens
        }
        
        uint256 allowance = IERC20(token).allowance(owner, spender);
        if (allowance < requiredAmount) {
            console.log("FAILED: Insufficient token approval:");
            console.log("  Token: %s", token);
            console.log("  Owner: %s", owner);
            console.log("  Spender: %s", spender);
            console.log("  Current allowance: %s", allowance);
            console.log("  Required amount: %s", requiredAmount);
            console.log("");
            console.log("Please run Step 2: node scripts/2-maker-approve-tokens.js");
            revert("Insufficient token approval. Run Step 2 first.");
        }
        
        console.log("SUCCESS: Token approval verified:");
        console.log("  Allowance: %s >= Required: %s", allowance, requiredAmount);
    }

    function _fundResolver(address token, address resolver, uint256 amount) internal {
        if (token == address(0) || amount == 0) {
            return; // No funding needed for native tokens or zero amounts
        }

        uint256 resolverBalance = IERC20(token).balanceOf(resolver);
        console.log("Resolver current balance: %s", resolverBalance);
        console.log("Required amount: %s", amount);

        if (resolverBalance >= amount) {
            console.log("SUCCESS: Resolver already has sufficient tokens");
            return;
        }

        uint256 amountNeeded = amount - resolverBalance;
        console.log("Funding resolver with %s tokens", amountNeeded);

        vm.startBroadcast(_deployerAddress);
        
        // Transfer tokens from deployer to resolver
        IERC20(token).transfer(resolver, amountNeeded);
        
        vm.stopBroadcast();

        // Verify the transfer
        uint256 newResolverBalance = IERC20(token).balanceOf(resolver);
        if (newResolverBalance >= amount) {
            console.log("SUCCESS: Resolver funded with tokens");
            console.log("  New balance: %s", newResolverBalance);
        } else {
            revert("Resolver funding failed");
        }
    }

    function _approveResolverTokens(address token, address resolver, address spender, uint256 amount) internal {
        if (token == address(0) || amount == 0) {
            return; // No approval needed for native tokens or zero amounts
        }

        // Check current allowance
        uint256 currentAllowance = IERC20(token).allowance(resolver, spender);
        console.log("Resolver current allowance: %s", currentAllowance);
        console.log("Required allowance: %s", amount);

        if (currentAllowance >= amount) {
            console.log("SUCCESS: Resolver already has sufficient allowance");
            return;
        }

        console.log("Approving resolver tokens to Limit Order Protocol");

        // Use resolver's arbitrary calls to approve tokens
        address[] memory targets = new address[](1);
        bytes[] memory arguments = new bytes[](1);
        targets[0] = token;
        arguments[0] = abi.encodePacked(IERC20(token).approve.selector, abi.encode(spender, amount));

        vm.startBroadcast(_deployerAddress);
        IResolverExample(resolver).arbitraryCalls(targets, arguments);
        vm.stopBroadcast();

        // Verify the approval
        uint256 newAllowance = IERC20(token).allowance(resolver, spender);
        if (newAllowance >= amount) {
            console.log("SUCCESS: Resolver tokens approved");
            console.log("  New allowance: %s", newAllowance);
        } else {
            revert("Resolver token approval failed");
        }
    }

    function _mintToken(address token, address to, uint256 amount) internal {
        vm.startBroadcast(_deployerAddress);
        
        if (token == address(0)) {
            // Handle native token transfers
            (bool success,) = to.call{ value: amount }("");
            if (!success) {
                revert NativeTokenTransferFailure();
            }
            console.log("Sent %s native tokens to: %s", amount, to);
        } else if (block.chainid == 31337) {
            // Localhost: mint tokens
            TokenCustomDecimalsMock(token).mint(to, amount);
            console.log("Minted %s tokens for: %s", amount, to);
        } else {
            // Live testnet: transfer from deployer
            IERC20(token).transfer(to, amount);
            console.log("Transferred %s tokens from deployer to: %s", amount, to);
        }
        
        vm.stopBroadcast();
    }

    function _replaceTokensForMocks(
        Config memory config
    ) internal {
        if (block.chainid != 31337) {
            return;
        }

        if (config.srcToken != address(0)) {
            config.srcToken = _deployMockToken(config, config.srcToken);

            console.log("Mock src token deployed at: %s", config.srcToken);
        }

        if (config.dstToken != address(0)) {
            config.dstToken = _deployMockToken(config, config.dstToken);

            console.log("Mock dst token deployed at: %s", config.dstToken);
        }
    }

    function _deployMockToken(Config memory config, address tokenAddress) internal returns (address) {
        if (block.chainid != 31337) {
            return tokenAddress;
        }

        vm.startBroadcast(_deployerAddress);
        TokenCustomDecimalsMock token = new TokenCustomDecimalsMock(
            ERC20(tokenAddress).name(), ERC20(tokenAddress).symbol(), 0, ERC20(tokenAddress).decimals()
        );

        token.transferOwnership(config.deployer);
        vm.stopBroadcast();

        return address(token);
    }

    function _deployResolverExample(
        DeploymentConfig memory deploymentConfig
    ) internal {
        if (block.chainid != 31337) {
            return;
        }

        vm.startBroadcast(_deployerAddress);
        new ResolverExample(IEscrowFactory(_escrowFactory), IOrderMixin(deploymentConfig.limitOrderProtocol), _deployerAddress);
        vm.stopBroadcast();
    }

    function _defineFeeTokens() internal {
        FEE_TOKEN[1] = 0x6B175474E89094C44Da98b954EedeAC495271d0F; // Mainnet (DAI)
        FEE_TOKEN[56] = 0x1AF3F329e8BE154074D8769D1FFa4eE058B1DBc3; // BSC (DAI)
        FEE_TOKEN[137] = 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063; // Polygon (DAI)
        FEE_TOKEN[43114] = 0xd586E7F844cEa2F87f50152665BCbc2C279D8d70; // Avalanche (DAI)
        FEE_TOKEN[100] = 0xe91D153E0b41518A2Ce8Dd3D7944Fa863463a97d; // Gnosis (wXDAI)
        FEE_TOKEN[42161] = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1; // Arbitrum One (DAI)
        FEE_TOKEN[10] = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1; // Optimism (DAI)
        FEE_TOKEN[8453] = 0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb; // Base (DAI)
        FEE_TOKEN[59144] = 0x4AF15ec2A0BD43Db75dd04E62FAA3B8EF36b00d5; // Linea (DAI)
        FEE_TOKEN[146] = 0x29219dd400f2Bf60E5a23d13Be72B486D4038894; // Sonic (USDC)
        FEE_TOKEN[130] = 0x20CAb320A855b39F724131C69424240519573f81; // Unichain (DAI)
        FEE_TOKEN[31337] = 0x6B175474E89094C44Da98b954EedeAC495271d0F; // Localhost (DAI)
    }
}
