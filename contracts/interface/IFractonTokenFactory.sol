// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IFractonTokenFactory {
  function getowner() external view returns (address);

  function getDAOAddress() external view returns (address);

  function getVaultAddress() external view returns (address);

  function getSwapAddress() external view returns (address);

  function getPoolFundingVaultAddress() external view returns (address);
}
