// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import '../interface/IFractonFFT.sol';
import '../interface/IFractonTokenFactory.sol';

contract FractonFFT is ERC20, IFractonFFT {
  using SafeMath for uint256;

  mapping(address => bool) private _isExcludedFromFee;

  address public _factory;

  uint256 public vaultPercent = 20;
  uint256 public pfVaultPercent = 0;

  modifier onlyOwner() {
    address owner = IFractonTokenFactory(_factory).getowner();
    require(msg.sender == owner, 'Fracton: caller is not the owner');
    _;
  }

  modifier onlyDAO() {
    address dao = IFractonTokenFactory(_factory).getDAOAddress();
    require(msg.sender == dao, 'Fracton: caller is not Fracton DAO');
    _;
  }

  modifier onlySwap() {
    address dao = IFractonTokenFactory(_factory).getSwapAddress();
    require(msg.sender == dao, 'Fracton: caller is not swap');
    _;
  }

  constructor(string memory name_, string memory symbol_)
    ERC20(name_, symbol_)
  {
    _factory = msg.sender;

    _isExcludedFromFee[_factory] = true;
    _isExcludedFromFee[IFractonTokenFactory(_factory).getSwapAddress()] = true;
    _isExcludedFromFee[
      IFractonTokenFactory(_factory).getPoolFundingVaultAddress()
    ] = true;
    _isExcludedFromFee[IFractonTokenFactory(_factory).getVaultAddress()] = true;
    _isExcludedFromFee[address(this)] = true;
  }

  function swapmint(uint256 amount, address to)
    external
    virtual
    override
    onlySwap
    returns (bool)
  {
    _mint(to, amount);
    return true;
  }

  /* math that SafeMath doesn't include */
  function ceil(uint256 a, uint256 m) internal pure returns (uint256) {
    uint256 c = a.add(m);
    uint256 d = c.sub(1);
    return d.div(m).mul(m);
  }

  function cut(uint256 value, uint256 percent) public pure returns (uint256) {
    if (percent == 0) {
      return 0;
    } else {
      uint256 roundValue = ceil(value, percent);
      uint256 cutValue = roundValue.mul(percent).div(10000);
      return cutValue;
    }
  }

  function transfer(address to, uint256 value)
    public
    virtual
    override(ERC20, IFractonFFT)
    returns (bool)
  {
    address from = _msgSender();
    require(value <= balanceOf(from), 'from balance insufficient');

    if (isExcludedFromFee(from) || isExcludedFromFee(to)) {
      _transfer(from, to, value);
    } else {
      uint256 vaultFee = cut(value, vaultPercent);
      uint256 pfVaultFee = cut(value, pfVaultPercent);
      uint256 tokensToTransfer = value.sub(vaultFee).sub(pfVaultFee);

      _transfer(
        from,
        IFractonTokenFactory(_factory).getVaultAddress(),
        vaultFee
      );
      _transfer(
        from,
        IFractonTokenFactory(_factory).getPoolFundingVaultAddress(),
        pfVaultFee
      );
      _transfer(from, to, tokensToTransfer);
    }
    return true;
  }

  function multiTransfer(address[] memory receivers, uint256[] memory amounts)
    public
    virtual
    override
  {
    for (uint256 i = 0; i < receivers.length; i++) {
      transfer(receivers[i], amounts[i]);
    }
  }

  function transferFrom(
    address from,
    address to,
    uint256 value
  ) public virtual override(ERC20, IFractonFFT) returns (bool) {
    address spender = _msgSender();
    require(value <= balanceOf(from), 'from balance insufficient');

    if (isExcludedFromFee(from) || isExcludedFromFee(to)) {
      _spendAllowance(from, spender, value);
      _transfer(from, to, value);
    } else {
      uint256 vaultFee = cut(value, vaultPercent);
      uint256 pfVaultFee = cut(value, pfVaultPercent);
      uint256 tokensToTransfer = value.sub(vaultFee).sub(pfVaultFee);
      _spendAllowance(from, spender, value);

      _transfer(
        from,
        IFractonTokenFactory(_factory).getVaultAddress(),
        vaultFee
      );
      _transfer(
        from,
        IFractonTokenFactory(_factory).getPoolFundingVaultAddress(),
        pfVaultFee
      );
      _transfer(from, to, tokensToTransfer);
    }

    return true;
  }

  function burnFrom(address from, uint256 value)
    external
    virtual
    override
    returns (bool)
  {
    address spender = _msgSender();
    if (from != spender) {
      _spendAllowance(from, spender, value);
    }
    _burn(from, value);
    return true;
  }

  function excludeFromFee(address account) public onlyDAO returns (bool) {
    _isExcludedFromFee[account] = true;
    return true;
  }

  function batchExcludeFromFee(address[] memory accounts)
    external
    onlyDAO
    returns (bool)
  {
    for (uint256 i = 0; i < accounts.length; i++) {
      _isExcludedFromFee[accounts[i]] = true;
    }
    return true;
  }

  function includeInFee(address account) external onlyDAO returns (bool) {
    _isExcludedFromFee[account] = false;
    return true;
  }

  function updateFee(uint256 vaultPercent_, uint256 pfVaultPercent_)
    external
    override
    onlyDAO
    returns (bool)
  {
    vaultPercent = vaultPercent_;
    pfVaultPercent = pfVaultPercent_;

    emit SetPercent(vaultPercent_, pfVaultPercent_);
    return true;
  }

  function isExcludedFromFee(address account)
    public
    view
    virtual
    override
    returns (bool)
  {
    return _isExcludedFromFee[account];
  }
}
