// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

interface IPair {
  function decimals() external view returns (uint8);
  function token0() external view returns (address);
  function token1() external view returns (address);
  function stable() external view returns (bool);
  function totalSupply() external view returns (uint256);
  function balanceOf(address account) external view returns (uint256);
  function getReserves() external view returns (uint256 _reserve0, uint256 _reserve1, uint256 _blockTimestampLast);
  function claimable0(address _user) external view returns (uint256);
  function claimable1(address _user) external view returns (uint256);
  function claimFees() external returns (uint256, uint256);
  function getAmountOut(uint256, address) external view returns (uint256);
}