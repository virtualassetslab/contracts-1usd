// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IProxy {
    function implementation() external view returns (address);
    function upgradeTo(address implementation) external;
}
