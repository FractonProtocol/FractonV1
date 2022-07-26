// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import '@openzeppelin/contracts/token/ERC1155/ERC1155.sol';
import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import '@openzeppelin/contracts/utils/Counters.sol';
import '@openzeppelin/contracts/token/ERC1155/extensions/ERC1155URIStorage.sol';
import '../interface/IFractonMiniNFT.sol';
import '../interface/IFractonTokenFactory.sol';

contract FractonMiniNFT is ERC1155URIStorage, IFractonMiniNFT {
  using Counters for Counters.Counter;

  Counters.Counter private _tokenIds; //counter of round. 0 reserves for people's NFT

  bool public saleIsActive; //is open for blindbox mint

  address private _factory; //factory deployer address

  uint256 public blindBoxPrice = 1E17; //blindbox price

  uint256 public constant ROUND_CAP = 1000;

  mapping(uint256 => bool) public roundSucceed; //is round succeed for users' claiming into people's NFT

  mapping(uint256 => uint256) private _totalAmount;

  modifier onlyDAO() {
    address dao = IFractonTokenFactory(_factory).getDAOAddress();
    require(msg.sender == dao, 'Fracton: caller is not Fracton DAO');
    _;
  }

  modifier onlyOwner() {
    address owner = IFractonTokenFactory(_factory).getowner();
    require(msg.sender == owner, 'Fracton: caller is not the owner');
    _;
  }

  /**
   * @dev Total amount of tokens in with a given id.
   */
  constructor(string memory uri_) ERC1155(uri_) {
    _factory = msg.sender;
  }

  receive() external payable {}

  function startNewRound(uint256 sellingPrice)
    external
    override
    onlyDAO
    returns (bool)
  {
    require(!saleIsActive, 'Fracton: active sale exists');
    _tokenIds.increment();
    saleIsActive = true;
    blindBoxPrice = sellingPrice;

    emit StartNewRound(block.number, sellingPrice);
    return true;
  }

  function closeRound() external override onlyDAO returns (bool) {
    saleIsActive = false;

    emit CloseRound(block.number);
    return true;
  }

  function mintBlindBox(uint256 amount)
    external
    payable
    override
    returns (uint256)
  {
    uint256 round = _tokenIds.current();
    require(saleIsActive, 'Fracton: sale not active');
    require(
      blindBoxPrice * amount <= msg.value,
      'Fracton: Ether value not enough'
    );
    _totalAmount[round] += amount;
    if (totalSupply(round) >= ROUND_CAP) {
      saleIsActive = false;
    }
    _mint(msg.sender, round, amount, '');
    return amount;
  }

  function claimBlindBox(uint256 tokenID) external override returns (uint256) {
    require(roundSucceed[tokenID], 'Fracton: round is not succeed');

    uint256 amount = balanceOf(msg.sender, tokenID);
    require(amount > 0, 'Fracton: no blindbox to claim');

    _totalAmount[tokenID] -= amount;
    _totalAmount[0] += amount;
    _burn(msg.sender, tokenID, amount);
    _mint(msg.sender, 0, amount, '');

    emit ClaimBlindBox(msg.sender, tokenID, amount);
    return amount;
  }

  // Withdraw fundrasing ethers for purchasing NFT
  function withdrawEther() external override onlyDAO returns (bool) {
    uint256 amount = address(this).balance;
    address dao = msg.sender;
    payable(dao).transfer(amount);

    emit WithdrawEther(msg.sender, amount);
    return true;
  }

  function updateDefaultURI(string memory defaultURI) external onlyOwner {
    _setURI(defaultURI);
  }

  function updateTokenURI(uint256 tokenId, string memory tokenURI)
    external
    onlyOwner
  {
    _setURI(tokenId, tokenURI);
  }

  function updateRoundSucceed(uint256 round)
    external
    override
    onlyDAO
    returns (bool)
  {
    require(_totalAmount[round] >= ROUND_CAP, 'Fracton: Not achieve yet');
    roundSucceed[round] = true;

    emit UpdateRoundSucceed(round, block.number);
    return roundSucceed[round];
  }

  function updateBlindBoxPrice(uint256 newPrice)
    external
    override
    onlyDAO
    returns (bool)
  {
    blindBoxPrice = newPrice;

    emit UpdateBlindBoxPrice(newPrice);
    return true;
  }

  function totalSupply(uint256 id) public view override returns (uint256) {
    return _totalAmount[id];
  }

  function burn(uint256 amount) external {
    _totalAmount[0] -= amount;
    _burn(msg.sender, 0, amount);
  }

  function currentRound() public view returns (uint256) {
    return _tokenIds.current();
  }

  function swapmint(uint256 amount, address to)
    external
    virtual
    override
    returns (bool)
  {
    require(
      msg.sender == IFractonTokenFactory(_factory).getSwapAddress(),
      'Fracton: caller is not swap'
    );
    _totalAmount[0] += amount;
    _mint(to, 0, amount, '');
    return true;
  }
}
