// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { ERC20 } from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

/**
 * @title Standard ERC-20 Token for Cross-Chain Swaps
 */
contract SwapToken is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1000000 * 10 ** 18); // 1M tokens
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
