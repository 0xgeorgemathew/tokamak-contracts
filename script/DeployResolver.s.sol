// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { stdJson } from "forge-std/StdJson.sol";

import { ResolverExample } from "contracts/mocks/ResolverExample.sol";
import { IEscrowFactory } from "contracts/interfaces/IEscrowFactory.sol";
import { IOrderMixin } from "limit-order-protocol/contracts/interfaces/IOrderMixin.sol";
import { DeploymentUtils } from "./DeploymentUtils.s.sol";

contract DeployResolver is DeploymentUtils {
    using stdJson for string;

    function run() external {
        address deployer = vm.envAddress("DEPLOYER_ADDRESS");

        // Read existing deployments to get factory and LOP addresses
        string memory json = vm.readFile("deployments.json");

        uint256 chainId = block.chainid;
        string memory networkName;

        if (chainId == 11155111) {
            networkName = "sepolia";
        } else if (chainId == 10143) {
            networkName = "monad";
        } else {
            revert("Unsupported network");
        }

        string memory basePath = string.concat(".contracts.", networkName);
        address escrowFactory = json.readAddress(string.concat(basePath, ".escrowFactory"));
        address limitOrderProtocol = json.readAddress(string.concat(basePath, ".limitOrderProtocol"));
        address accessToken = json.readAddress(string.concat(basePath, ".accessToken"));
        address feeToken = json.readAddress(string.concat(basePath, ".feeToken"));
        address swapToken = json.readAddress(string.concat(basePath, ".swapToken"));

        console.log("Deploying ResolverExample to", networkName);
        console.log("EscrowFactory:", escrowFactory);
        console.log("LimitOrderProtocol:", limitOrderProtocol);
        console.log("Owner (deployerKey):", deployer);

        vm.startBroadcast();

        ResolverExample resolver = new ResolverExample(
            IEscrowFactory(escrowFactory),
            IOrderMixin(limitOrderProtocol),
            deployer // deployerKey as owner
        );

        vm.stopBroadcast();

        // Update deployments.json with resolver address
        DeploymentAddresses memory addrs = DeploymentAddresses({
            factory: escrowFactory,
            accessToken: accessToken,
            feeToken: feeToken,
            swapToken: swapToken,
            lop: limitOrderProtocol,
            resolver: address(0) // Will be updated after deployment
        });

        // Read current rescue delay from config
        uint32 rescueDelay = uint32(json.readUint(".config.rescueDelay"));

        updateDeploymentFile(networkName, chainId, deployer, rescueDelay, addrs);

        // Add resolver address to the deployment file
        _addResolverToDeploymentFile(networkName, address(resolver));

        console.log("");
        console.log("=== RESOLVER DEPLOYMENT SUMMARY ===");
        console.log("Network:", networkName);
        console.log("Resolver deployed at:", address(resolver));
        console.log("Owner (resolver operator):", deployer);
        console.log("Updated deployments.json");
    }

    function _addResolverToDeploymentFile(string memory networkName, address resolverAddress) internal {
        console.log("Adding resolver address to deployments.json...");
        console.log("Network:", networkName);
        console.log("Resolver:", resolverAddress);

        // Read current deployments.json
        string memory currentJson = vm.readFile("deployments.json");

        // For automated update, we'll use a Node.js script
        // Create the update command
        string[] memory inputs = new string[](5);
        inputs[0] = "node";
        inputs[1] = "-e";
        inputs[2] = string.concat(
            "const fs = require('fs'); ",
            "const data = JSON.parse(fs.readFileSync('deployments.json', 'utf8')); ",
            "data.contracts.",
            networkName,
            ".resolver = '",
            vm.toString(resolverAddress),
            "'; ",
            "data.lastUpdated = Math.floor(Date.now() / 1000); ",
            "fs.writeFileSync('deployments.json', JSON.stringify(data, null, 2));"
        );
        inputs[3] = "";
        inputs[4] = "";

        // Execute the update
        try vm.ffi(inputs) {
            console.log("Successfully updated deployments.json with resolver address");
        } catch {
            console.log("FFI failed. Please manually add this to your deployments.json:");
            console.log("In .contracts.", networkName, " add:");
            console.log('"resolver": "', vm.toString(resolverAddress), '"');
        }
    }
}
