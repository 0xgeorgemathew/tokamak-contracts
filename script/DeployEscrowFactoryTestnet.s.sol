// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { Script } from "forge-std/Script.sol";
import { TokenMock } from "solidity-utils/contracts/mocks/TokenMock.sol";
import { EscrowFactory } from "contracts/EscrowFactory.sol";
import { console } from "forge-std/console.sol";
import { DeploymentUtils } from "./DeploymentUtils.s.sol"; // <-- IMPORT

contract DeployEscrowFactoryTestnet is DeploymentUtils {
    uint32 public constant RESCUE_DELAY = 691200; // 8 days
    address public constant LOP = 0xa8D8F5f33af375ba0Eb0Ed15C46DA0757DE21b56;
    uint256 public constant SEPOLIA_CHAIN_ID = 11155111;
    string public constant NETWORK_NAME = "sepolia";

    function run() external {
        address deployer = vm.envAddress("DEPLOYER_ADDRESS");
        address feeBankOwner = deployer;

        vm.startBroadcast();

        TokenMock accessToken = new TokenMock("ACCESS TOKEN", "ACCESS");
        TokenMock feeToken = new TokenMock("FEE TOKEN", "FEE");
        TokenMock swapToken = new TokenMock("SEPOLIA SWAP TOKEN", "SSWAP");
        EscrowFactory escrowFactory = new EscrowFactory(LOP, feeToken, accessToken, feeBankOwner, RESCUE_DELAY, RESCUE_DELAY);
        //mint tokens


        vm.stopBroadcast();

        // --- Use the utility to write to the file ---
        DeploymentAddresses memory addrs = DeploymentAddresses({
            factory: address(escrowFactory),
            accessToken: address(accessToken),
            feeToken: address(feeToken),
            swapToken: address(swapToken),
            lop: LOP
        });

        updateDeploymentFile(NETWORK_NAME, SEPOLIA_CHAIN_ID, deployer, RESCUE_DELAY, addrs);

        console.log("=== SEPOLIA DEPLOYMENT SUMMARY ===");
        console.log("Escrow Factory deployed at: ", address(escrowFactory));
        console.log("Deployment info saved to deployments.json");
    }
}
