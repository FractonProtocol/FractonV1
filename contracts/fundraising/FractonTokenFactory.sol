// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import '@openzeppelin/contracts/utils/Create2.sol';
import '../library/FractonMiniNFTHelper.sol';
import '../library/FractonFFTHelper.sol';
import '../interface/IFractonTokenFactory.sol';
import '../interface/IFractonSwap.sol';

contract FractonTokenFactory is IFractonTokenFactory {
  address private _owner;
  address private _FractonGovernor;
  address public FractonSwap;
  address private _FractonVault;
  address private _FractonPFVault; //poolfundingvault
  address public pendingVault;
  address public pendingPFVault;

  mapping(address => address) public projectToMiniNFT;
  mapping(address => address) public projectToFFT;

  constructor(
    address daoAddress,
    address swapAddress,
    address vaultAddress,
    address PFvaultAddress
  ) {
    _owner = msg.sender;
    _FractonGovernor = daoAddress;
    _FractonVault = vaultAddress;
    _FractonPFVault = PFvaultAddress;
    FractonSwap = swapAddress;

    pendingVault = _FractonVault;
    pendingPFVault = _FractonPFVault;
  }

  modifier onlyFactoryOwner() {
    require(msg.sender == _owner, 'Fracton: invalid caller');
    _;
  }

  modifier onlyDao() {
    require(msg.sender == _FractonGovernor, 'Fracton: caller is not dao');
    _;
  }

  function createCollectionPair(
    address projectAddress,
    bytes32 salt,
    string memory miniNFTBaseUri,
    string memory name,
    string memory symbol
  ) external onlyFactoryOwner returns (address, address) {
    require(
      projectToMiniNFT[projectAddress] == address(0) &&
        projectToFFT[projectAddress] == address(0),
      'Already exist.'
    );

    address newMiniNFTContract = Create2.deploy(
      0,
      salt,
      FractonMiniNFTHelper.getBytecode(miniNFTBaseUri)
    );

    require(newMiniNFTContract != address(0), 'Fracton: deploy MiniNFT Failed');

    address newFFTContract = Create2.deploy(
      0,
      salt,
      FractonFFTHelper.getBytecode(name, symbol)
    );

    require(newFFTContract != address(0), 'Fracton: deploy FFT Failed');

    projectToMiniNFT[projectAddress] = newMiniNFTContract;
    projectToFFT[projectAddress] = newFFTContract;

    require(
      IFractonSwap(FractonSwap).updatePoolRelation(
        newMiniNFTContract,
        newFFTContract,
        projectAddress
      )
    );

    return (newMiniNFTContract, newFFTContract);
  }

  function updateDao(address daoAddress) external onlyDao returns (bool) {
    _FractonGovernor = daoAddress;
    return true;
  }

  function signDaoReq() external onlyFactoryOwner returns (bool) {
    _FractonVault = pendingVault;
    _FractonPFVault = pendingPFVault;

    return true;
  }

  function updateVault(address pendingVault_) external onlyDao returns (bool) {
    pendingVault = pendingVault_;
    return true;
  }

  function updatePFVault(address pendingPFVault_)
    external
    onlyDao
    returns (bool)
  {
    pendingPFVault = pendingPFVault_;
    return true;
  }

  function getowner() external view override returns (address) {
    return _owner;
  }

  function getDAOAddress() external view override returns (address) {
    return _FractonGovernor;
  }

  function getSwapAddress() external view override returns (address) {
    return FractonSwap;
  }

  function getVaultAddress() external view override returns (address) {
    return _FractonVault;
  }

  function getPoolFundingVaultAddress()
    external
    view
    override
    returns (address)
  {
    return _FractonPFVault;
  }
}
