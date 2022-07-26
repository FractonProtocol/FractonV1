// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

interface IFractonFFT is IERC20 {
  event SetPercent(uint256 vaultPercent, uint256 pfVaultPercent);

  function swapmint(uint256 amount, address to) external returns (bool);

  function transfer(address to, uint256 value) external returns (bool);

  function multiTransfer(address[] memory receivers, uint256[] memory amounts)
    external;

  function transferFrom(
    address from,
    address to,
    uint256 value
  ) external returns (bool);

  function burnFrom(address from, uint256 value) external returns (bool);

  function isExcludedFromFee(address account) external view returns (bool);

  function updateFee(uint256 vaultPercent_, uint256 pfVaultPercent_)
    external
    returns (bool);
}
