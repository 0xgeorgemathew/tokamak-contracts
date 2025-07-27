// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

import { Script } from "forge-std/Script.sol";
import { TokenMock } from "solidity-utils/contracts/mocks/TokenMock.sol";
import { EscrowFactory } from "contracts/EscrowFactory.sol";

// solhint-disable no-console
import { console } from "forge-std/console.sol";

contract DeployEscrowFactoryTestnet is Script {
    uint32 public constant RESCUE_DELAY = 691200; // 8 days

    // Use a dummy LOP address for testing (you can update this)
    address public constant LOP = 0xa8D8F5f33af375ba0Eb0Ed15C46DA0757DE21b56;

    function run() external {
        address deployer = vm.envAddress("DEPLOYER_ADDRESS");
        address feeBankOwner = deployer;

        vm.startBroadcast();

        // Deploy mock ACCESS TOKEN (same as Monad)
        TokenMock accessToken = new TokenMock("ACCESS TOKEN", "ACCESS");
        console.log("ACCESS TOKEN deployed at: ", address(accessToken));

        // Deploy mock FEE TOKEN (same as Monad)
        TokenMock feeToken = new TokenMock("FEE TOKEN", "FEE");
        console.log("FEE TOKEN deployed at: ", address(feeToken));

        // Deploy EscrowFactory with SAME INTERFACE as Monad
        EscrowFactory escrowFactory = new EscrowFactory(
            LOP,
            feeToken,
            accessToken,
            feeBankOwner,
            RESCUE_DELAY,
            RESCUE_DELAY
        );

        vm.stopBroadcast();

        console.log("=== SEPOLIA DEPLOYMENT SUMMARY ===");
        console.log("Escrow Factory deployed at: ", address(escrowFactory));
        console.log("LOP address: ", LOP);
        console.log("Fee token: ", address(feeToken));
        console.log("Access token: ", address(accessToken));
        console.log("Deployer/Owner: ", deployer);
        console.log("Rescue delay (seconds): ", RESCUE_DELAY);
    }
}
// solhint-enable no-console
