// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {Deployments} from "forge-deploy/library/Deployments.sol";

import {IProxy} from "../src/interface/IProxy.sol";
import {IStablecoin, Count, PoolIndex} from "../src/interface/IStablecoin.sol";

contract DeploymentsTest is Test {
    using Deployments for Deployments.EnumerableDeployments;

    Deployments.EnumerableDeployments enumerableDeployments;

    function test_MainnetContractsInitializedProperly() public {
        _contractInitializedProperly("mainnet", "1USD", 19_975_530);
    }

    function _contractInitializedProperly(
        string memory network,
        string memory configName,
        uint256 _forkAtBlock
    ) internal {
        vm.createSelectFork(network, _forkAtBlock);
        enumerableDeployments.hydrate(network);
        string memory config = vm.readFile(_configFile(network, configName));
        string memory deploymentName = vm.parseJsonString(config, ".deployment-name");
        address stablecoin = _get(deploymentName);

        assertEq(IStablecoin(stablecoin).name(), vm.parseJsonString(config, ".name"));
        assertEq(IStablecoin(stablecoin).symbol(), vm.parseJsonString(config, ".symbol"));

        uint256 one = 10 ** IStablecoin(stablecoin).decimals();
        // TODO read JSON dynamic array length via something like this:
        //     uint256 poolsLength = vm.parseJsonStringArray(config, ".pools").length;
        // As of 2024-07-31, this currently fails due to https://github.com/foundry-rs/foundry/issues/8467
        uint256 POOLS_LENGTH = 3;
        for (uint256 i = 0; i < POOLS_LENGTH; i++) {
            (Count signatures, uint256 threshold, uint256 limit, , , ) = IStablecoin(stablecoin).viewMintPool(
                PoolIndex.wrap(i)
            );

            uint256 configSignatures = vm.parseJsonUint(
                config,
                string.concat(".pools[", vm.toString(i), "].signatures")
            );
            uint256 configThreshold = vm.parseJsonUint(config, string.concat(".pools[", vm.toString(i), "].threshold"));
            uint256 configLimit = vm.parseJsonUint(config, string.concat(".pools[", vm.toString(i), "].limit"));

            assertEq(Count.unwrap(signatures), configSignatures);
            assertEq(threshold, configThreshold * one);
            assertEq(limit, configLimit * one);
        }

        _assertRole(
            stablecoin,
            IStablecoin(stablecoin).MINTER_ROLE(),
            vm.parseJsonAddressArray(config, ".roles.minter")
        );
        _assertRole(
            stablecoin,
            IStablecoin(stablecoin).MINT_RATIFIER_ROLE(),
            vm.parseJsonAddressArray(config, ".roles.mint_ratifier")
        );
        _assertRole(
            stablecoin,
            IStablecoin(stablecoin).REDEMPTION_ADMIN_ROLE(),
            vm.parseJsonAddressArray(config, ".roles.redemption_admin")
        );
        _assertRole(
            stablecoin,
            IStablecoin(stablecoin).PAUSER_ROLE(),
            vm.parseJsonAddressArray(config, ".roles.pauser")
        );
        _assertRole(
            stablecoin,
            IStablecoin(stablecoin).DEFAULT_ADMIN_ROLE(),
            vm.parseJsonAddressArray(config, ".roles.admin")
        );
    }

    function _get(string memory key) internal view returns (address) {
        return enumerableDeployments.get(key).address_;
    }

    function _configFile(string memory network, string memory name) private view returns (string memory) {
        return string.concat(vm.projectRoot(), "/script/configs/", network, "/", name, ".json");
    }

    function _assertRole(address stablecoin, bytes32 role, address[] memory addresses) private {
        for (uint256 i = 0; i < addresses.length; i++) {
            assertTrue(IStablecoin(stablecoin).hasRole(role, addresses[i]));
        }
    }
}
