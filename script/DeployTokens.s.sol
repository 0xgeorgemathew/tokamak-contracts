// --- START OF FILE: script/DeployTokens.s.sol ---

// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { DeploymentUtils } from "./DeploymentUtils.s.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { AccessToken } from "../contracts/tokens/AccessToken.sol";
import { SwapToken } from "../contracts/tokens/SwapToken.sol";

/**
 * @title Deploy Access and Swap Tokens
 */
contract DeployTokens is DeploymentUtils {
    using stdJson for string;

    function run() external {
        address deployer = vm.envAddress("DEPLOYER_ADDRESS");
        uint32 rescueDelay = uint32(vm.envOr("RESCUE_DELAY", uint256(7 days)));
        uint256 chainId = block.chainid;
        string memory networkName = _getNetworkName(chainId);

        console.log("=== DEPLOYING TOKENS ON", networkName, "===");
        vm.startBroadcast();

        AccessToken accessToken = new AccessToken();
        console.log("Access Token deployed at:", address(accessToken));

        string memory tokenName = string.concat(networkName, " Swap Token");
        string memory tokenSymbol = string.concat(_getNetworkPrefix(chainId), "SWAP");
        SwapToken swapToken = new SwapToken(tokenName, tokenSymbol);
        console.log("Swap Token deployed at:", address(swapToken));

        vm.stopBroadcast();

        DeploymentAddresses memory addrs = DeploymentAddresses({
            factory: address(0),
            accessToken: address(accessToken),
            feeToken: address(0),
            swapToken: address(swapToken),
            lop: address(0)
        });

        updateDeploymentFile(networkName, chainId, deployer, rescueDelay, addrs);
        console.log("Tokens saved to deployments.json");
    }

    function _getNetworkName(
        uint256 chainId
    ) internal pure returns (string memory) {
        if (chainId == 11155111) return "sepolia";
        if (chainId == 10143) return "monad";
        return "unknown";
    }

    function _getNetworkPrefix(
        uint256 chainId
    ) internal pure returns (string memory) {
        if (chainId == 11155111) return "S";
        if (chainId == 10143) return "M";
        return "U";
    }

}

// --- END OF FILE ---
