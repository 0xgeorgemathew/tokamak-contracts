// solhint-disable no-console
contract DeployEscrowSrc is Script {
    using stdJson for string;

    function run() external {
        // --- Configuration ---
        address deployerAddress = vm.envAddress("DEPLOYER_ADDRESS");
        address makerAddress = vm.envAddress("MAKER_ADDRESS");
        IResolverExample resolver = IResolverExample(vm.envAddress("RESOLVER_ADDRESS"));
        IOrderMixin limitOrderProtocol = IOrderMixin(vm.envAddress("LOP_ADDRESS"));
        address srcToken = vm.envAddress("SRC_TOKEN_ADDRESS");
        address dstToken = vm.envAddress("DST_TOKEN_ADDRESS");
        uint256 srcAmount = vm.envUint("SRC_AMOUNT");
        uint256 safetyDeposit = vm.envUint("SAFETY_DEPOSIT");

        // --- Load Secrets and Pre-signed Order ---
        string memory secretsJson = vm.readFile("./data/swap-secrets.json");
        bytes32 hashlock = bytes32(secretsJson.readBytes(".secretHash"));
        bytes32 r = bytes32(secretsJson.readBytes(".signatureData.r"));
        bytes32 vs = bytes32(secretsJson.readBytes(".signatureData.vs"));
        IOrderMixin.Order memory order = abi.decode(secretsJson.readBytes(".signatureData.order"), (IOrderMixin.Order));
        bytes32 orderHash = limitOrderProtocol.hashOrder(order);

        // --- Build Timelocks ---
        Timelocks timelocks = TimelocksSettersLib.init(300, 600, 900, 1200, 300, 600, 900, 0);

        // --- Build Immutables for Escrow ---
        IBaseEscrow.Immutables memory immutables = IBaseEscrow.Immutables({
            orderHash: orderHash,
            amount: srcAmount,
            maker: Address.wrap(uint160(makerAddress)),
            taker: Address.wrap(uint160(address(resolver))),
            token: Address.wrap(uint160(srcToken)),
            hashlock: hashlock,
            safetyDeposit: safetyDeposit,
            timelocks: timelocks
        });

        // --- Build TakerTraits and Arguments for LOP ---
        (TakerTraits takerTraits, bytes memory args) =
            CrossChainTestLib.buildTakerTraits(true, false, true, false, address(0), "", "", 0);

        vm.startBroadcast(deployerAddress);

        // Fund resolver with source tokens if needed (for takerAsset)
        if (IERC20(srcToken).balanceOf(address(resolver)) < srcAmount) {
            IERC20(srcToken).transfer(address(resolver), srcAmount);
        }

        // Have resolver approve LOP
        address[] memory targets = new address[](1);
        bytes[] memory arguments = new bytes[](1);
        targets[0] = srcToken;
        arguments[0] = abi.encodePacked(IERC20.approve.selector, address(limitOrderProtocol), srcAmount);
        resolver.arbitraryCalls(targets, arguments);

        // Call the resolver to deploy the source escrow
        resolver.deploySrc(immutables, order, r, vs, srcAmount, takerTraits, args);

        vm.stopBroadcast();

        console.log(" DeployEscrowSrc script finished.");
        // Corrected logging: Use separate calls and the appropriate function for the type.
        console.log("Order Hash:");
        console.logBytes32(orderHash);
        // The timelocks value will be captured from the event logs by the orchestrator
    }
}
