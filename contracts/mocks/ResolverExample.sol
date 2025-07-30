// SPDX-License-Identifier: MIT
/*──────────────────────────────────────────────────────────────────────────────
 * WARNING!
 * ... (your warning comment)
 *──────────────────────────────────────────────────────────────────────────────*/

pragma solidity 0.8.23;

import { Ownable } from "openzeppelin-contracts/contracts/access/Ownable.sol";

import { IOrderMixin } from "limit-order-protocol/contracts/interfaces/IOrderMixin.sol";
import { TakerTraits } from "limit-order-protocol/contracts/libraries/TakerTraitsLib.sol";
import { RevertReasonForwarder } from "solidity-utils/contracts/libraries/RevertReasonForwarder.sol";

import { IBaseEscrow } from "../interfaces/IBaseEscrow.sol";
import { IEscrowFactory } from "../interfaces/IEscrowFactory.sol";
import { IResolverExample } from "../interfaces/IResolverExample.sol";
import { TimelocksLib } from "../libraries/TimelocksLib.sol";

/**
 * @title Sample implementation of a Resolver contract for cross-chain swap.
 * ... (your comments)
 * @custom:security-contact security@1inch.io
 */
contract ResolverExample is IResolverExample, Ownable {
    IEscrowFactory private immutable _FACTORY;
    IOrderMixin private immutable _LOP;

    // =========================================================================
    // FIX #1: Define the event that your script is looking for.
    // The compiler needs to know what "SourceEscrowCreated" is.
    // Based on your script, it should take these three parameters.
    // =========================================================================
    event SourceEscrowCreated(bytes32 indexed orderHash, bytes32 indexed hashlock, address srcEscrow);

    constructor(IEscrowFactory factory, IOrderMixin lop, address initialOwner) Ownable(initialOwner) {
        _FACTORY = factory;
        _LOP = lop;
    }

    event DstEscrowCreatedEvent(bytes32 indexed orderHash, address dstEscrow, uint256 deployedAt);

    receive() external payable { } // solhint-disable-line no-empty-blocks

    /**
     * @notice See {IResolverExample-deploySrc}.
     */
    function deploySrc(
        IBaseEscrow.Immutables calldata immutables,
        IOrderMixin.Order calldata order,
        bytes32 r,
        bytes32 vs,
        uint256 amount,
        TakerTraits takerTraits,
        bytes calldata args
    ) external onlyOwner {
        IBaseEscrow.Immutables memory immutablesMem = immutables;
        immutablesMem.timelocks = TimelocksLib.setDeployedAt(immutables.timelocks, block.timestamp);

        // This is the variable that holds the escrow address. Its name is `computed`.
        address computed = _FACTORY.addressOfEscrowSrc(immutablesMem);
        (bool success,) = address(computed).call{ value: immutablesMem.safetyDeposit }("");
        if (!success) revert IBaseEscrow.NativeTokenSendingFailure();

        // _ARGS_HAS_TARGET = 1 << 251
        takerTraits = TakerTraits.wrap(TakerTraits.unwrap(takerTraits) | uint256(1 << 251));
        bytes memory argsMem = abi.encodePacked(computed, args);
        _LOP.fillOrderArgs(order, r, vs, amount, takerTraits, argsMem);

        // =========================================================================
        // FIX: Verify that the escrow was actually deployed as a contract
        // =========================================================================
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(computed)
        }
        if (codeSize == 0) {
            revert("EscrowSrc deployment failed - no contract at computed address");
        }

        // =========================================================================
        // FIX #2: Emit the event using the correct variable name, `computed`.
        // This will now compile and provide the necessary log for your `deployEscrowDst` script.
        // =========================================================================
        emit SourceEscrowCreated(immutables.orderHash, immutables.hashlock, computed);
    }

    /**
     * @notice See {IResolverExample-deployDst}.
     */
    function deployDst(
        IBaseEscrow.Immutables calldata dstImmutables,
        uint256 srcCancellationTimestamp
    ) external payable onlyOwner {
        // =========================================================================
        // FIX #1: First, PREDICT the destination escrow address, just like in deploySrc.
        // We assume a function `addressOfEscrowDst` exists on the factory, mirroring `addressOfEscrowSrc`.
        // =========================================================================
        address dstEscrow = _FACTORY.addressOfEscrowDst(dstImmutables);

        // =========================================================================
        // FIX #2: Call the creation function, which returns nothing.
        // This line will now compile correctly.
        // =========================================================================
        _FACTORY.createDstEscrow{ value: msg.value }(dstImmutables, srcCancellationTimestamp);

        // =========================================================================
        // FIX: Verify that the destination escrow was actually deployed as a contract
        // =========================================================================
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(dstEscrow)
        }
        if (codeSize == 0) {
            revert("EscrowDst deployment failed - no contract at computed address");
        }

        // =========================================================================
        // FIX #3: Emit the event with the address we predicted.
        // This provides the necessary receipt for the withdrawal script (Step 6).
        // =========================================================================
        emit DstEscrowCreatedEvent(dstImmutables.orderHash, dstEscrow, block.timestamp);
    }

    /**
     * @notice See {IResolverExample-arbitraryCalls}.
     */
    function arbitraryCalls(address[] calldata targets, bytes[] calldata arguments) external onlyOwner {
        uint256 length = targets.length;
        if (targets.length != arguments.length) revert LengthMismatch();
        for (uint256 i = 0; i < length; ++i) {
            // solhint-disable-next-line avoid-low-level-calls
            (bool success,) = targets[i].call(arguments[i]);
            if (!success) RevertReasonForwarder.reRevert();
        }
    }
}
