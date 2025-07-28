// solhint-disable no-console

// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { Script } from "forge-std/Script.sol";
import { EscrowFactory } from "contracts/EscrowFactory.sol";
import { console } from "forge-std/console.sol";
import { DeploymentUtils } from "./DeploymentUtils.s.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract DeployEscrowFactoryMonad is DeploymentUtils {
    using stdJson for string;

    uint32 public constant RESCUE_DELAY = 691200; // 8 days
    address public constant LOP = 0x689F20F2e2901f32E255e8016Ad9D58b61D353b3;
    uint256 public constant MONAD_CHAIN_ID = 10143;
    string public constant NETWORK_NAME = "monad";

    function run() external {
        address deployer = vm.envAddress("DEPLOYER_ADDRESS");
        address feeBankOwner = deployer;

        // 1. Read the deployments file to get prerequisite token addresses
        console.log("Reading existing addresses from deployments.json for '%s'...", NETWORK_NAME);
        string memory json = vm.readFile("deployments.json");

        string memory basePath = string.concat(".contracts.", NETWORK_NAME);
        address accessToken = json.readAddress(string.concat(basePath, ".accessToken"));
        address feeToken = json.readAddress(string.concat(basePath, ".feeToken"));
        address swapToken = json.readAddress(string.concat(basePath, ".swapToken"));

        // 2. Validate that the addresses were loaded correctly
        require(accessToken != address(0), "Monad accessToken not found in deployments.json");
        require(feeToken != address(0), "Monad feeToken not found in deployments.json");
        require(swapToken != address(0), "Monad swapToken not found in deployments.json");

        console.log("Loaded Access Token:", accessToken);
        console.log("Loaded Fee Token:", feeToken);

        // 3. Deploy the factory using the loaded addresses
        vm.startBroadcast();

        console.log("Deploying EscrowFactory to Monad...");
        EscrowFactory escrowFactory =
            new EscrowFactory(LOP, IERC20(feeToken), IERC20(accessToken), feeBankOwner, RESCUE_DELAY, RESCUE_DELAY);

        vm.stopBroadcast();

        // 4. Use the utility to write the new factory address back to the file
        DeploymentAddresses memory addrs = DeploymentAddresses({
            factory: address(escrowFactory),
            accessToken: accessToken, // Preserve loaded value
            feeToken: feeToken, // Preserve loaded value
            swapToken: swapToken, // Preserve loaded value
            lop: LOP
        });

        updateDeploymentFile(NETWORK_NAME, MONAD_CHAIN_ID, deployer, RESCUE_DELAY, addrs);

        console.log("");
        console.log("=== MONAD DEPLOYMENT SUMMARY ===");
        console.log("Escrow Factory deployed at: ", address(escrowFactory));
        console.log("Deployment info saved to deployments.json");
    }
}
