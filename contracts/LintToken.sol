// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

/// @title Seolint token — $LINT
/// @notice Fixed supply 10,000,000,000 LINT, minted entirely to the deployer
///         at construction. No further minting, no tax, no owner powers.
///         Burnable (ERC20Burnable) because the Seolint Scan burn lane spends
///         50,000 LINT per extra Scan via burnFrom (the Scan contract must be
///         approved first). Claim pool: the deployer funds the three
///         LintClaim contracts with 2,000,000,000 LINT each (60% of supply).
contract LintToken is ERC20, ERC20Burnable {
    uint256 public constant TOTAL_SUPPLY = 10_000_000_000 ether;

    constructor() ERC20("Seolint", "LINT") {
        _mint(msg.sender, TOTAL_SUPPLY);
    }
}
