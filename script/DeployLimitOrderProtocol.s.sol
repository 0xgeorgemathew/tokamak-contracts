// solhint-disable-next-line no-unused-import
// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { LimitOrderProtocol } from "contracts/LimitOrderProtocol.sol";
import { IWETH } from "@1inch/solidity-utils/contracts/interfaces/IWETH.sol";
import { DeploymentUtils } from "./DeploymentUtils.s.sol";

contract DeployLimitOrderProtocol is DeploymentUtils {
    using stdJson for string;
    // WETH addresses for different networks
    address private constant _SEPOLIA_WETH = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;
    address private constant _MONAD_WETH = 0x4200000000000000000000000000000000000006; // Monad testnet WETH

    function run() external {
        address deployer = vm.envAddress("DEPLOYER_ADDRESS");

        uint256 chainId = block.chainid;
        string memory networkName;
        address wethAddress;

        // Determine network and WETH address
        if (chainId == 11155111) {
            networkName = "sepolia";
            wethAddress = _SEPOLIA_WETH;
        } else if (chainId == 10143) {
            networkName = "monad";
            wethAddress = _MONAD_WETH;
        } else {
            revert("Unsupported network");
        }

        console.log("Deploying LimitOrderProtocol to", networkName);
        console.log("Chain ID:", vm.toString(chainId));
        console.log("Deployer:", deployer);
        console.log("WETH address:", wethAddress);

        vm.startBroadcast();

        // Deploy LimitOrderProtocol
        LimitOrderProtocol limitOrderProtocol = new LimitOrderProtocol(IWETH(wethAddress));

        vm.stopBroadcast();

        console.log("LimitOrderProtocol deployed at:", address(limitOrderProtocol));

        // Update deployments.json - read existing addresses to preserve them
        DeploymentAddresses memory addrs = DeploymentAddresses({
            factory: address(0),
            accessToken: address(0),
            feeToken: address(0),
            swapToken: address(0),
            lop: address(limitOrderProtocol),
            resolver: address(0)
        });

        // Read existing addresses from deployments.json
        try vm.readFile(DEPLOYMENT_FILE) returns (string memory existingJson) {
            string memory networkPath = string.concat(".contracts.", networkName);
            
            try vm.parseJsonAddress(existingJson, string.concat(networkPath, ".escrowFactory")) returns (address factory) {
                addrs.factory = factory;
            } catch {}
            
            try vm.parseJsonAddress(existingJson, string.concat(networkPath, ".accessToken")) returns (address accessToken) {
                addrs.accessToken = accessToken;
            } catch {}
            
            try vm.parseJsonAddress(existingJson, string.concat(networkPath, ".feeToken")) returns (address feeToken) {
                addrs.feeToken = feeToken;
            } catch {}
            
            try vm.parseJsonAddress(existingJson, string.concat(networkPath, ".swapToken")) returns (address swapToken) {
                addrs.swapToken = swapToken;
            } catch {}
            
            try vm.parseJsonAddress(existingJson, string.concat(networkPath, ".resolver")) returns (address resolver) {
                addrs.resolver = resolver;
            } catch {}
        } catch {}

        uint32 rescueDelay = uint32(vm.envOr("RESCUE_DELAY", uint256(7 days)));
        updateDeploymentFile(networkName, chainId, deployer, rescueDelay, addrs);

        console.log("Deployment completed and deployments.json updated");

        // Only verify on Ethereum networks (not Monad)
        if (chainId != 10143) {
            console.log("To verify the contract, run:");
            console.log("forge verify-contract", vm.toString(address(limitOrderProtocol)));
            console.log("contracts/LimitOrderProtocol.sol:LimitOrderProtocol");
            console.log("--chain-id", vm.toString(chainId));
            console.log("--constructor-args", vm.toString(abi.encode(wethAddress)));
        }
    }

}
