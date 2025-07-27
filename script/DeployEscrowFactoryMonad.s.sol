// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

import { Script } from "forge-std/Script.sol";
import { TokenMock } from "solidity-utils/contracts/mocks/TokenMock.sol";
import { EscrowFactory } from "contracts/EscrowFactory.sol";

// solhint-disable no-console
import { console } from "forge-std/console.sol";

contract DeployEscrowFactoryMonad is Script {
    uint32 public constant RESCUE_DELAY = 691200; // 8 days

    // Your deployed LOP address on Monad
    address public constant LOP = 0x689F20F2e2901f32E255e8016Ad9D58b61D353b3;

    function run() external {
        address deployer = vm.envAddress("DEPLOYER_ADDRESS");
        address feeBankOwner = deployer;

        vm.startBroadcast();

        // Deploy mock ACCESS TOKEN
        TokenMock accessToken = new TokenMock("ACCESS TOKEN", "ACCESS");
        console.log("ACCESS TOKEN deployed at: ", address(accessToken));

        // Deploy mock FEE TOKEN
        TokenMock feeToken = new TokenMock("FEE TOKEN", "FEE");
        console.log("FEE TOKEN deployed at: ", address(feeToken));

        // Deploy EscrowFactory with mock tokens
        EscrowFactory escrowFactory = new EscrowFactory(LOP, feeToken, accessToken, feeBankOwner, RESCUE_DELAY, RESCUE_DELAY);

        vm.stopBroadcast();

        console.log("=== DEPLOYMENT SUMMARY ===");
        console.log("Escrow Factory deployed at: ", address(escrowFactory));
        console.log("LOP address: ", LOP);
        console.log("Fee token: ", address(feeToken));
        console.log("Access token: ", address(accessToken));
        console.log("Deployer/Owner: ", deployer);
        console.log("Rescue delay (seconds): ", RESCUE_DELAY);
    }
}
// solhint-enable no-console
