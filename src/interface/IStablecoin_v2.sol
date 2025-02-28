// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

type Account is uint24;
type Count is uint256;
type OpIndex is uint256;
type PoolIndex is uint256;

interface IStablecoin_v2 {
    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);
    function MINTER_ROLE() external view returns (bytes32);
    function MINT_RATIFIER_ROLE() external view returns (bytes32);
    function ACCOUNT_ADMIN_ROLE() external view returns (bytes32);
    function PAUSER_ROLE() external view returns (bytes32);
    function FROZEN_ROLE() external view returns (bytes32);
    function initializeV2() external;
    function name() external returns (string memory);
    function symbol() external returns (string memory);
    function decimals() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address account, uint256 amount) external returns (bool);
    function viewMintPool(PoolIndex poolIndex) external view returns (Count, uint256, uint256, uint256, Count, Count);
    function viewRedemptionAccountsCount() external view returns (uint256);
    function canAccountRedeem(Account account) external view returns (bool);
    function viewMinimumRedemptionAmount() external view returns (uint256);
    function viewMinimumBridgingAmount() external view returns (uint256);
    function getRoleAdmin(bytes32 role) external view returns (bytes32);
    function getRoleMemberCount(bytes32 role) external view returns (uint256);
    function hasRole(bytes32 role, address account) external view returns (bool);
}
