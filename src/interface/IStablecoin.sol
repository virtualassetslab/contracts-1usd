// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

type Count is uint256;
type PoolIndex is uint256;

interface IStablecoin {
    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);
    function MINTER_ROLE() external view returns (bytes32);
    function MINT_RATIFIER_ROLE() external view returns (bytes32);
    function REDEMPTION_ADMIN_ROLE() external view returns (bytes32);
    function PAUSER_ROLE() external view returns (bytes32);
    function initialize(string memory name_, string memory symbol_) external;
    function name() external returns (string memory);
    function symbol() external returns (string memory);
    function decimals() external view returns (uint256);
    function viewMintPool(PoolIndex poolIndex) external view returns (Count, uint256, uint256, uint256, Count, Count);
    function getRoleMemberCount(bytes32 role) external returns (uint256);
    function hasRole(bytes32 role, address account) external returns (bool);
}
