// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import '@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol';
import '@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import '@openzeppelin/contracts/token/ERC1155/IERC1155.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol';
import '@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol';

import '../interface/IFractonMiniNFT.sol';
import '../interface/IFractonFFT.sol';
import '../interface/IFractonSwap.sol';
import '../interface/IFractonTokenFactory.sol';

contract FractonSwap is
  ERC721Holder,
  ERC1155Holder,
  Ownable,
  IFractonSwap,
  VRFConsumerBaseV2
{
  uint256 public swapRate = 1E21;
  uint256 public fftTax = 3E18;
  uint256 public nftTax = 3;
  address public tokenFactory;
  address public vrfRescuer;

  mapping(uint256 => ChainLinkRequest) public chainLinkRequests;
  mapping(address => uint256[]) public NFTIds;
  mapping(address => address) public NFTtoMiniNFT;
  mapping(address => address) public miniNFTtoFFT;

  // Chinlink VRF
  VRFCoordinatorV2Interface COORDINATOR;
  bytes32 public keyHash;
  uint32 public callbackGasLimit = 1000000;
  uint32 public numWords = 1;
  uint16 public requestConfirmations = 3;
  uint64 public subscriptionId;
  uint256[] public s_randomWords;

  constructor(
    address vrfCoordinator_,
    address vrfRescuer_,
    bytes32 keyHash_,
    uint64 subscriptionId_
  ) VRFConsumerBaseV2(vrfCoordinator_) {
    COORDINATOR = VRFCoordinatorV2Interface(vrfCoordinator_);
    vrfRescuer = vrfRescuer_;
    keyHash = keyHash_;
    subscriptionId = subscriptionId_;
  }

  modifier onlyDAO() {
    address dao = IFractonTokenFactory(tokenFactory).getDAOAddress();
    require(msg.sender == dao, 'Fracton: caller is not Fracton DAO');
    _;
  }

  modifier onlyFactoryOrOwner() {
    require(
      msg.sender == tokenFactory || msg.sender == owner(),
      'Invalid Caller'
    );
    _;
  }

  function updatePoolRelation(
    address miniNFT,
    address FFT,
    address NFT
  ) external virtual override onlyFactoryOrOwner returns (bool) {
    miniNFTtoFFT[miniNFT] = FFT;
    NFTtoMiniNFT[NFT] = miniNFT;
    emit UpdatePoolRelation(msg.sender, miniNFT, FFT, NFT);
    return true;
  }

  function poolClaim(address miniNFTContract, uint256 tokenID)
    external
    virtual
    override
    returns (bool)
  {
    require(
      miniNFTtoFFT[miniNFTContract] != address(0),
      'swap: invalid contract'
    );
    require(IFractonMiniNFT(miniNFTContract).claimBlindBox(tokenID) > 0);

    emit PoolClaim(msg.sender, miniNFTContract, tokenID);
    return true;
  }

  function swapMiniNFTtoFFT(
    address miniNFTContract,
    uint256 tokenID,
    uint256 amount
  ) external virtual override returns (bool) {
    require(
      miniNFTtoFFT[miniNFTContract] != address(0),
      'swap: invalid contract'
    );

    uint256 miniNFTBalance = IERC1155(miniNFTContract).balanceOf(
      msg.sender,
      tokenID
    );
    require(miniNFTBalance >= amount, 'swap: balance insufficient');

    IERC1155(miniNFTContract).safeTransferFrom(
      msg.sender,
      address(this),
      tokenID,
      amount,
      ''
    );

    require(
      IFractonFFT(miniNFTtoFFT[miniNFTContract]).swapmint(
        amount * swapRate,
        msg.sender
      )
    );

    emit SwapMiniNFTtoFFT(msg.sender, miniNFTContract, tokenID, amount);
    return true;
  }

  function swapFFTtoMiniNFT(address miniNFTContract, uint256 miniNFTAmount)
    external
    virtual
    override
    returns (bool)
  {
    require(
      miniNFTtoFFT[miniNFTContract] != address(0),
      'swap: invalid contract'
    );
    require(
      IERC1155(miniNFTContract).balanceOf(address(this), 0) >= miniNFTAmount,
      'swap:insufficient miniNFT in pool'
    );
    uint256 FFTamount = miniNFTAmount * swapRate;
    uint256 taxfee = miniNFTAmount * fftTax;

    require(
      IFractonFFT(miniNFTtoFFT[miniNFTContract]).burnFrom(msg.sender, FFTamount)
    );

    require(
      IFractonFFT(miniNFTtoFFT[miniNFTContract]).transferFrom(
        msg.sender,
        IFractonTokenFactory(tokenFactory).getVaultAddress(),
        taxfee
      )
    );
    IERC1155(miniNFTContract).safeTransferFrom(
      address(this),
      msg.sender,
      0,
      miniNFTAmount,
      ''
    );

    emit SwapFFTtoMiniNFT(msg.sender, miniNFTContract, miniNFTAmount);
    return true;
  }

  function swapMiniNFTtoNFT(address NFTContract)
    external
    virtual
    override
    returns (bool)
  {
    address miniNFTContract = NFTtoMiniNFT[NFTContract];
    require(miniNFTContract != address(0), 'swap: invalid contract');
    require(NFTIds[NFTContract].length > 0, 'swap: no NFT left');

    uint256 requestId = COORDINATOR.requestRandomWords(
      keyHash,
      subscriptionId,
      requestConfirmations,
      callbackGasLimit,
      numWords
    );

    chainLinkRequests[requestId] = ChainLinkRequest(msg.sender, NFTContract);

    emit SendChainlinkVRF(requestId, msg.sender, NFTContract);
    return true;
  }

  function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords)
    internal
    virtual
    override
  {
    address sender = chainLinkRequests[requestId].sender;

    address NFTContract = chainLinkRequests[requestId].nft;

    address miniNFTContract = NFTtoMiniNFT[NFTContract];

    uint256 NFTNumber = NFTIds[NFTContract].length;

    require(NFTNumber > 0, 'swap: no NFT left');

    uint256 NFTIndex = randomWords[0] % NFTNumber;

    uint256 NFTID = NFTIds[NFTContract][NFTIndex];

    NFTIds[NFTContract][NFTIndex] = NFTIds[NFTContract][NFTNumber - 1];
    NFTIds[NFTContract].pop();

    IERC1155(miniNFTContract).safeTransferFrom(
      sender,
      address(this),
      0,
      1000,
      ''
    );

    IFractonMiniNFT(miniNFTContract).burn(1000);

    IERC1155(miniNFTContract).safeTransferFrom(
      sender,
      IFractonTokenFactory(tokenFactory).getVaultAddress(),
      0,
      nftTax,
      ''
    );

    IERC721(NFTContract).transferFrom(address(this), sender, NFTID);

    emit SwapMiniNFTtoNFT(sender, NFTContract, NFTID);
  }

  function swapNFTtoMiniNFT(
    address NFTContract,
    address fromOwner,
    uint256 tokenId
  ) external virtual override onlyDAO returns (bool) {
    address miniNFTContract = NFTtoMiniNFT[NFTContract];

    require(miniNFTContract != address(0), 'swap: invalid contract');

    IERC721(NFTContract).safeTransferFrom(fromOwner, address(this), tokenId);

    require(IFractonMiniNFT(miniNFTContract).swapmint(1000, fromOwner));

    return true;
  }

  function withdrawERC20(address project, uint256 amount)
    external
    onlyDAO
    returns (bool)
  {
    require(
      IERC20(project).transfer(msg.sender, amount),
      'swap: withdraw failed'
    );
    return true;
  }

  function withdrawERC721(address airdropContract, uint256 tokenId)
    external
    onlyDAO
    returns (bool)
  {
    require(
      NFTtoMiniNFT[airdropContract] == address(0),
      'swap: cannot withdraw ProjectNFT'
    );

    IERC721(airdropContract).safeTransferFrom(
      address(this),
      msg.sender,
      tokenId
    );

    return true;
  }

  function withdrawERC1155(
    address airdropContract,
    uint256 tokenId,
    uint256 amount
  ) external onlyDAO returns (bool) {
    require(
      miniNFTtoFFT[airdropContract] == address(0),
      'swap: cannot withdraw ProjectNFT'
    );

    IERC1155(airdropContract).safeTransferFrom(
      address(this),
      msg.sender,
      tokenId,
      amount,
      ''
    );

    return true;
  }

  function updateFactory(address factory_) external onlyOwner returns (bool) {
    require(tokenFactory == address(0), 'swap: factory has been set');
    require(factory_ != address(0), 'swap: factory can not be 0 address');

    tokenFactory = factory_;

    emit UpdateFactory(factory_);
    return true;
  }

  function updateTax(uint256 fftTax_, uint256 nftTax_)
    external
    onlyDAO
    returns (bool)
  {
    fftTax = fftTax_;
    nftTax = nftTax_;

    emit UpdateTax(fftTax_, nftTax_);
    return true;
  }

  function updateCallbackGasLimit(uint32 gasLimit_)
    external
    override
    onlyDAO
    returns (bool)
  {
    callbackGasLimit = gasLimit_;
    return true;
  }

  // only used when Chainlink VRF Service is down
  function emergencyUpdateVrf(address vrfCoordinator_) external {
    require(msg.sender == vrfRescuer, 'swap: invalid caller');
    require(vrfCoordinator_ != address(0), 'swap: invaild coordiantor address');

    COORDINATOR = VRFCoordinatorV2Interface(vrfCoordinator_);
  }

  function updateVrfSubscriptionId(uint64 subscriptionId_)
    external
    override
    onlyDAO
    returns (bool)
  {
    subscriptionId = subscriptionId_;
    return true;
  }

  function onERC721Received(
    address operator,
    address from,
    uint256 tokenId,
    bytes calldata data
  ) public virtual override returns (bytes4) {
    NFTIds[msg.sender].push(tokenId);
    return super.onERC721Received(operator, from, tokenId, data);
  }

  function numberOfNFT(address NFTContract) external view returns (uint256) {
    return NFTIds[NFTContract].length;
  }
}
