// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import '../fundraising/FractonFFT.sol';

library FractonFFTHelper {
  function getBytecode(string memory name, string memory symbol)
    public
    pure
    returns (bytes memory)
  {
    bytes memory bytecode = type(FractonFFT).creationCode;
    return abi.encodePacked(bytecode, abi.encode(name, symbol));
  }
}
