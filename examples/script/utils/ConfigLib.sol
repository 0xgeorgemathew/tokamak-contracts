// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

import { Vm } from "forge-std/Vm.sol";
import { stdJson } from "forge-std/StdJson.sol";

struct Config {
    uint32 cancellationDstTimelock;
    uint32 cancellationSrcTimelock;
    address deployer;
    uint256 dstAmount;
    address dstToken;
    address escrowFactory;
    address limitOrderProtocol;
    address maker;
    uint32 publicCancellationSrcTimelock;
    uint32 publicWithdrawalDstTimelock;
    uint32 publicWithdrawalSrcTimelock;
    address resolver;
    uint256 safetyDeposit;
    string secret;
    uint256 srcAmount;
    address srcToken;
    string[] stages;
    uint32 withdrawalDstTimelock;
    uint32 withdrawalSrcTimelock;
}

struct DeploymentConfig {
    uint256 chainId;
    address escrowFactory;
    address accessToken;
    address feeToken;
    address swapToken;
    address limitOrderProtocol;
    address resolver;
}

library ConfigLib {
    using stdJson for string;

    function getConfig(Vm vm, string memory fileName) internal view returns (Config memory) {
        string memory json = vm.readFile(fileName);
        bytes memory data = vm.parseJson(json);
 
        Config memory config = abi.decode(data, (Config));

        return config;
    }

    function getDeploymentConfig(Vm vm, uint256 chainId) internal view returns (DeploymentConfig memory) {
        string memory deploymentsJson = vm.readFile("./deployments.json");
        
        string memory networkName;
        if (chainId == 11155111) {
            networkName = "sepolia";
        } else if (chainId == 10143) {
            networkName = "monad";
        } else {
            revert("Unsupported network");
        }

        string memory basePath = string.concat(".contracts.", networkName);
        
        DeploymentConfig memory deploymentConfig = DeploymentConfig({
            chainId: chainId,
            escrowFactory: deploymentsJson.readAddress(string.concat(basePath, ".escrowFactory")),
            accessToken: deploymentsJson.readAddress(string.concat(basePath, ".accessToken")),
            feeToken: deploymentsJson.readAddress(string.concat(basePath, ".feeToken")),
            swapToken: deploymentsJson.readAddress(string.concat(basePath, ".swapToken")),
            limitOrderProtocol: deploymentsJson.readAddress(string.concat(basePath, ".limitOrderProtocol")),
            resolver: deploymentsJson.readAddress(string.concat(basePath, ".resolver"))
        });

        return deploymentConfig;
    }

    function getCrossChainTokenAddress(Vm vm, uint256 chainId) internal view returns (address) {
        string memory deploymentsJson = vm.readFile("./deployments.json");
        
        string memory networkName;
        if (chainId == 11155111) {
            networkName = "monad"; // Get opposite chain for cross-chain
        } else if (chainId == 10143) {
            networkName = "sepolia"; // Get opposite chain for cross-chain
        } else {
            revert("Unsupported network");
        }

        string memory basePath = string.concat(".contracts.", networkName);
        return deploymentsJson.readAddress(string.concat(basePath, ".swapToken"));
    }
}