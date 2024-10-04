// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {Deployments} from "forge-deploy/library/Deployments.sol";

contract DeploymentsTest is Test {
    using Deployments for Deployments.EnumerableDeployments;

    Deployments.EnumerableDeployments enumerableDeployments;
    string[] skipSepolia = new string[](0);
    string[] skipMainnet = new string[](0);

    function test_MainnetDeployedAddressesMatch() public {
        _deployedAddressesMatch("mainnet", skipMainnet);
    }

    function _deployedAddressesMatch(string memory network, string[] memory skip) internal {
        vm.createSelectFork(network);
        enumerableDeployments.hydrate(network);

        for (uint256 i = 0; i < enumerableDeployments.length(); i++) {
            string memory key = enumerableDeployments.keyAt(i);

            if (_shouldSkip(key, skip)) {
                continue;
            }

            assertEq(
                enumerableDeployments.getLocalBytecode(key),
                enumerableDeployments.getDeployedBytecode(key),
                string.concat(
                    "Local bytecode for ",
                    key,
                    " does not match deployed bytecode at ",
                    network,
                    " address ",
                    vm.toString(enumerableDeployments.get(key).address_),
                    "."
                )
            );
        }
    }

    function _shouldSkip(string memory key, string[] memory skip) internal pure returns (bool) {
        if (skip.length == 0) {
            return false;
        }

        for (uint256 j = 0; j < skip.length; j++) {
            if (keccak256(abi.encodePacked(key)) == keccak256(abi.encodePacked(skip[j]))) {
                return true;
            }
        }

        return false;
    }
}
