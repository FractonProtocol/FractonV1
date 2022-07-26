// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol';

contract Fracton is ERC20, ERC20Burnable {
  constructor() ERC20('Fracton', 'FT') {
    _mint(msg.sender, 1E26);
  }
}
