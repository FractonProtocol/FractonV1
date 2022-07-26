// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import '../fundraising/FractonMiniNFT.sol';

library FractonMiniNFTHelper {
  function getBytecode(string memory uri) public pure returns (bytes memory) {
    bytes memory bytecode = type(FractonMiniNFT).creationCode;
    return abi.encodePacked(bytecode, abi.encode(uri));
  }
}
