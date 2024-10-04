// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IStablecoin {
  function DEFAULT_ADMIN_ROLE() external view returns (bytes32);

  function MINTER_ROLE() external view returns (bytes32);

  function MINT_RATIFIER_ROLE() external view returns (bytes32);

  function REDEMPTION_ADMIN_ROLE() external view returns (bytes32);

  function REDEMPTION_ADDRESS_ROLE() external view returns (bytes32);

  function PAUSER_ROLE() external view returns (bytes32);

  function decimals() external view returns (uint256);

  function initialize(string memory name, string memory symbol) external;

  function pushMintPool(uint256 signatures, uint256 threshold, uint256 limit) external;

  function grantRole(bytes32 role, address account) external;

  function revokeRole(bytes32 role, address account) external;
}
