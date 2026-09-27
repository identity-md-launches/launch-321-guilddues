// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Guild (GILD), the fixed-supply currency of the Sepolia GuildDues toy.
/// @dev The project factory receives the entire supply at construction.
contract LaunchToken is ERC20 {
    constructor() ERC20("Guild", "GILD") {
        _mint(msg.sender, 1_000_000_000e18);
    }
}
