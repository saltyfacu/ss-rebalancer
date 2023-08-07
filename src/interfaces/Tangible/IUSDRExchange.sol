// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

interface IUSDRExchange {
  function swapFromUnderlying(uint256 amountIn, address to)
        external
        returns (uint256 amountOut);
  function swapToUnderlying(uint256 amountIn, address to)
        external
        returns (uint256);
}