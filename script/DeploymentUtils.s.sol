// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { stdJson } from "forge-std/StdJson.sol";

contract DeploymentUtils is Script {
    string private constant DEPLOYMENT_FILE = "deployments.json";

    struct DeploymentAddresses {
        address factory;
        address accessToken;
        address feeToken;
        address swapToken;
        address lop;
    }

    /**
     * @notice Reads deployments.json, finds or adds the entry for the network,
     *         and writes a completely new file with the updated data.
     */
    function updateDeploymentFile(
        string memory networkToUpdate,
        uint256 chainId,
        address deployer,
        uint32 rescueDelay,
        DeploymentAddresses memory addrs
    ) internal {
        string memory newJson;
        string memory newNetworkEntry = _createNetworkEntryJson(networkToUpdate, chainId, addrs);

        try vm.readFile(DEPLOYMENT_FILE) returns (string memory existingJson) {
            // File exists. Rebuild it with the updated entry.
            newJson = _rebuildJson(existingJson, networkToUpdate, newNetworkEntry);
            console.log("Updating '%s' entry in deployments.json...", networkToUpdate);
        } catch {
            // File does not exist. Create a new one.
            newJson = _createNewJson(deployer, rescueDelay, newNetworkEntry);
            console.log("Creating new deployments.json file...");
        }

        vm.writeFile(DEPLOYMENT_FILE, newJson);
    }

    /**
     * @notice Rebuilds the entire JSON object, replacing or adding the entry for `networkToUpdate`.
     */
    function _rebuildJson(
        string memory existingJson,
        string memory networkToUpdate,
        string memory newNetworkEntry
    ) private view returns (string memory) {
        // Use Foundry's StdJson to read top-level keys
        // ---- FIX 1: Store deployer as `address`, not `string` ----
        address existingDeployer = stdJson.readAddress(existingJson, ".deployer");
        uint256 rescueDelay = stdJson.readUint(existingJson, ".config.rescueDelay");

        // We can't easily parse a nested object, so we'll manually extract the `contracts` block.
        string memory contractsBlock = _getJsonSubObject(existingJson, "contracts");
        string[] memory existingNetworks = _getNetworkKeys(contractsBlock);

        // --- Build the new "contracts" object ---
        string memory newContractsJson = '"contracts": {\n';
        bool updated = false;

        for (uint256 i = 0; i < existingNetworks.length; i++) {
            string memory currentNetwork = existingNetworks[i];

            // Add a comma if it's not the first entry
            if (i > 0) {
                newContractsJson = string.concat(newContractsJson, ",\n");
            }

            if (keccak256(bytes(currentNetwork)) == keccak256(bytes(networkToUpdate))) {
                // This is the network we want to update. Use the new entry.
                newContractsJson = string.concat(newContractsJson, newNetworkEntry);
                updated = true;
            } else {
                // This is an old network. Keep its existing data.
                string memory oldEntry = _getJsonSubObject(contractsBlock, currentNetwork);
                newContractsJson = string.concat(newContractsJson, '"', currentNetwork, '": ', oldEntry);
            }
        }

        // If the network was not in the file, add it now.
        if (!updated) {
            if (existingNetworks.length > 0) {
                newContractsJson = string.concat(newContractsJson, ",\n");
            }
            newContractsJson = string.concat(newContractsJson, newNetworkEntry);
        }

        newContractsJson = string.concat(newContractsJson, "\n  }");

        // --- Assemble the final, complete JSON file ---
        return string(
            abi.encodePacked(
                "{\n",
                '  "lastUpdated": ',
                vm.toString(block.timestamp),
                ",\n",
                // ---- FIX 2: Call vm.toString on the address variable ----
                '  "deployer": "',
                vm.toString(existingDeployer),
                '",\n',
                '  "config": {\n',
                '    "rescueDelay": ',
                vm.toString(rescueDelay),
                "\n",
                "  },\n",
                "  ",
                newContractsJson,
                "\n",
                "}"
            )
        );
    }

    // --- JSON Parsing Helpers (Unchanged) ---

    function _getJsonSubObject(string memory json, string memory key) private pure returns (string memory) {
        string memory searchKey = string.concat('"', key, '":');
        bytes memory jsonBytes = bytes(json);
        bytes memory keyBytes = bytes(searchKey);

        uint256 start = 0;
        // Naive string search
        for (uint256 i = 0; i <= jsonBytes.length - keyBytes.length; i++) {
            bool isMatch = true;
            for (uint256 j = 0; j < keyBytes.length; j++) {
                if (jsonBytes[i + j] != keyBytes[j]) {
                    isMatch = false;
                    break;
                }
            }
            if (isMatch) {
                start = i + keyBytes.length;
                break;
            }
        }

        require(start > 0, "Key not found in JSON");

        // Skip whitespace to find the start of the object '{'
        for (uint256 i = start; i < jsonBytes.length; i++) {
            if (jsonBytes[i] == "{") {
                start = i;
                break;
            }
        }

        // Find the matching closing brace '}'
        uint256 braceCount = 1;
        uint256 end = 0;
        for (uint256 i = start + 1; i < jsonBytes.length; i++) {
            if (jsonBytes[i] == "{") braceCount++;
            if (jsonBytes[i] == "}") braceCount--;
            if (braceCount == 0) {
                end = i;
                break;
            }
        }
        require(end > 0, "Could not find matching brace");

        bytes memory result = new bytes(end - start + 1);
        for (uint256 i = 0; i <= end - start; i++) {
            result[i] = jsonBytes[start + i];
        }
        return string(result);
    }

    function _getNetworkKeys(
        string memory contractsBlock
    ) private pure returns (string[] memory) {
        // This is a simplified parser. It finds all occurrences of `"key": {`
        string[] memory keys = new string[](10); // Assume max 10 networks
        uint256 count = 0;
        bytes memory blockBytes = bytes(contractsBlock);

        for (uint256 i = 1; i < blockBytes.length; i++) {
            // Look for a quote followed by non-quote chars, then a quote and a colon
            if (blockBytes[i - 1] == '"') {
                uint256 keyStart = i;
                uint256 keyEnd = 0;
                for (uint256 j = i; j < blockBytes.length; j++) {
                    if (blockBytes[j] == '"') {
                        keyEnd = j - 1;
                        bool isObject = false;
                        for (uint256 k = j + 1; k < blockBytes.length; k++) {
                            if (blockBytes[k] == " " || blockBytes[k] == "\n" || blockBytes[k] == "\r") continue;
                            if (blockBytes[k] == ":") {
                                for (uint256 l = k + 1; l < blockBytes.length; l++) {
                                    if (blockBytes[l] == " " || blockBytes[l] == "\n" || blockBytes[l] == "\r") continue;
                                    if (blockBytes[l] == "{") isObject = true;
                                    break;
                                }
                            }
                            break;
                        }

                        if (isObject) {
                            bytes memory key = new bytes(keyEnd - keyStart + 1);
                            for (uint256 k = 0; k < key.length; k++) {
                                key[k] = blockBytes[keyStart + k];
                            }
                            keys[count++] = string(key);
                        }
                        i = j; // Continue search from here
                        break;
                    }
                }
            }
        }

        string[] memory finalKeys = new string[](count);
        for (uint256 i = 0; i < count; i++) {
            finalKeys[i] = keys[i];
        }
        return finalKeys;
    }

    // --- JSON Creation Helpers (Unchanged) ---

    function _createNetworkEntryJson(
        string memory network,
        uint256 chainId,
        DeploymentAddresses memory addrs
    ) private pure returns (string memory) {
        return string(
            abi.encodePacked(
                '    "',
                network,
                '": {\n',
                '      "chainId": ',
                vm.toString(chainId),
                ",\n",
                '      "escrowFactory": "',
                vm.toString(addrs.factory),
                '",\n',
                '      "accessToken": "',
                vm.toString(addrs.accessToken),
                '",\n',
                '      "feeToken": "',
                vm.toString(addrs.feeToken),
                '",\n',
                '      "swapToken": "',
                vm.toString(addrs.swapToken),
                '",\n',
                '      "limitOrderProtocol": "',
                vm.toString(addrs.lop),
                '"\n',
                "    }"
            )
        );
    }

    function _createNewJson(address deployer, uint32 rescueDelay, string memory firstNetworkEntry) private view returns (string memory) {
        return string(
            abi.encodePacked(
                "{\n",
                '  "lastUpdated": ',
                vm.toString(block.timestamp),
                ",\n",
                '  "deployer": "',
                vm.toString(deployer),
                '",\n',
                '  "config": {\n',
                '    "rescueDelay": ',
                vm.toString(rescueDelay),
                "\n",
                "  },\n",
                '  "contracts": {\n',
                firstNetworkEntry,
                "\n  }\n",
                "}"
            )
        );
    }
}
