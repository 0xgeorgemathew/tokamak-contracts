// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { Script } from "forge-std/Script.sol";
import { TokenMock } from "solidity-utils/contracts/mocks/TokenMock.sol";
import { EscrowFactory } from "contracts/EscrowFactory.sol";
import { console } from "forge-std/console.sol";
import { DeploymentUtils } from "./DeploymentUtils.s.sol"; // <-- IMPORT

contract DeployEscrowFactoryMonad is DeploymentUtils {
    uint32 public constant RESCUE_DELAY = 691200; // 8 days
    address public constant LOP = 0x689F20F2e2901f32E255e8016Ad9D58b61D353b3;
    uint256 public constant MONAD_CHAIN_ID = 10143; // Example Chain ID
    string public constant NETWORK_NAME = "monad";

    function run() external {
        address deployer = vm.envAddress("DEPLOYER_ADDRESS");
        address feeBankOwner = deployer;

        vm.startBroadcast();

        TokenMock accessToken = new TokenMock("ACCESS TOKEN", "ACCESS");
        TokenMock feeToken = new TokenMock("FEE TOKEN", "FEE");
        TokenMock swapToken = new TokenMock("MONAD SWAP TOKEN", "MSWAP");
        EscrowFactory escrowFactory = new EscrowFactory(LOP, feeToken, accessToken, feeBankOwner, RESCUE_DELAY, RESCUE_DELAY);
        //mint tokens
        //mint tokens
        feeToken.mint(deployer, 1000000);
        accessToken.mint(deployer, 1000000);
        swapToken.mint(deployer, 1000000);
        vm.stopBroadcast();

        // --- Use the utility to write to the file ---
        DeploymentAddresses memory addrs = DeploymentAddresses({
            factory: address(escrowFactory),
            accessToken: address(accessToken),
            feeToken: address(feeToken),
            swapToken: address(swapToken),
            lop: LOP
        });

        updateDeploymentFile(NETWORK_NAME, MONAD_CHAIN_ID, deployer, RESCUE_DELAY, addrs);

        console.log("=== MONAD DEPLOYMENT SUMMARY ===");
        console.log("Escrow Factory deployed at: ", address(escrowFactory));
        console.log("Deployment info saved to deployments.json");
    }
}
