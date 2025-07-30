// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { ERC20 } from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

/**
 * @title Access Control Token for Public Functions
 */
contract AccessToken is ERC20 {
    constructor() ERC20("1inch Cross-Chain Access", "ACCESS") {
        _mint(msg.sender, 10000 * 10 ** 18); // 10K tokens
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
