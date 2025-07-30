// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { DeploymentUtils } from "./DeploymentUtils.s.sol";

import { SwapToken } from "contracts/tokens/SwapToken.sol";

contract DeployTestTokens is DeploymentUtils {
    using stdJson for string;

    function run() external {
        address deployer = vm.envAddress("DEPLOYER_ADDRESS");
        address swapper = vm.envAddress("MAKER_ADDRESS"); // bravoKey

        uint256 chainId = block.chainid;
        string memory networkName;
        string memory tokenName;
        string memory tokenSymbol;

        if (chainId == 11155111) {
            networkName = "sepolia";
            tokenName = "Test USDC";
            tokenSymbol = "tUSDC";
        } else if (chainId == 10143) {
            networkName = "monad";
            tokenName = "Monad USDC";
            tokenSymbol = "mUSDC";
        } else {
            revert("Unsupported network");
        }

        console.log("Deploying test tokens to", networkName);
        console.log("Deployer (deployerKey):", deployer);
        console.log("Swapper (bravoKey):", swapper);

        // Read existing deployment addresses
        string memory json = vm.readFile("deployments.json");
        string memory basePath = string.concat(".contracts.", networkName);

        address existingFactory = json.readAddress(string.concat(basePath, ".escrowFactory"));
        address existingAccessToken = json.readAddress(string.concat(basePath, ".accessToken"));
        address existingFeeToken = json.readAddress(string.concat(basePath, ".feeToken"));
        address existingSwapToken = json.readAddress(string.concat(basePath, ".swapToken"));
        address existingLOP = json.readAddress(string.concat(basePath, ".limitOrderProtocol"));
        uint32 rescueDelay = uint32(json.readUint(".config.rescueDelay"));

        vm.startBroadcast();

        // Deploy test token
        SwapToken testToken = new SwapToken(tokenName, tokenSymbol);

        // Mint tokens to the swapper (bravoKey) for testing
        uint256 mintAmount = 10000 * 10 ** 18; // 10,000 tokens
        testToken.mint(swapper, mintAmount);

        vm.stopBroadcast();

        // Try to read existing resolver address, use zero address if not found
        address existingResolver = address(0);
        string memory resolverKey = string.concat(basePath, ".resolver");
        if (vm.keyExists(json, resolverKey)) {
            existingResolver = json.readAddress(resolverKey);
        }

        // Create deployment addresses preserving existing values
        DeploymentAddresses memory addrs = DeploymentAddresses({
            factory: existingFactory,
            accessToken: existingAccessToken,
            feeToken: existingFeeToken,
            swapToken: existingSwapToken, // Keep existing swap token
            lop: existingLOP,
            resolver: existingResolver
        });

        // Update the deployment file with all existing addresses
        updateDeploymentFile(networkName, chainId, deployer, rescueDelay, addrs);

        console.log("");
        console.log("=== TEST TOKEN DEPLOYMENT SUMMARY ===");
        console.log("Network:", networkName);
        console.log("Token name:", tokenName);
        console.log("Token symbol:", tokenSymbol);
        console.log("Token address:", address(testToken));
        console.log("Minted", mintAmount / 10 ** 18, "tokens to swapper:", swapper);
        console.log("Note: This is a separate test token, not the main swapToken");
        console.log("Deployment file updated to preserve existing addresses");
    }
}
