// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IFractonMiniNFT {
  event StartNewRound(uint256 blockNumber, uint256 sellingPrice);

  event CloseRound(uint256 blockNumber);

  event ClaimBlindBox(address owner, uint256 tokenID, uint256 amount);

  event WithdrawEther(address caller, uint256 amount);

  event UpdateRoundSucceed(uint256 round, uint256 blockNumber);

  event UpdateBlindBoxPrice(uint256 price);

  function startNewRound(uint256 sellingPrice) external returns (bool);

  function closeRound() external returns (bool);

  function mintBlindBox(uint256 amount) external payable returns (uint256);

  function claimBlindBox(uint256 tokenID) external returns (uint256);

  function withdrawEther() external returns (bool);

  function updateRoundSucceed(uint256 round) external returns (bool);

  function updateBlindBoxPrice(uint256 BBoxPrice) external returns (bool);

  function totalSupply(uint256 id) external view returns (uint256);

  function burn(uint256 amount) external;

  function swapmint(uint256 amount, address to) external returns (bool);
}
