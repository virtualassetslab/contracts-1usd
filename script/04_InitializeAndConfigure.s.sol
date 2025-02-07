// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";

import {Deployments} from "forge-deploy/library/Deployments.sol";
import {IStablecoin} from "./interfaces/IStablecoin.sol";

contract InitializeAndConfigureScript is Script {
    using Deployments for Deployments.EnumerableDeployments;
    Deployments.EnumerableDeployments enumerableDeployments;

    address private proxy;
    string private config;

    function run(string memory network, string memory configName) public {
        vm.createSelectFork(network);
        enumerableDeployments.hydrate(network);
        config = vm.readFile(_configFile(network, configName));

        // initialize
        string memory name = vm.parseJsonString(config, ".name");
        string memory symbol = vm.parseJsonString(config, ".symbol");
        string memory deploymentName = vm.parseJsonString(config, ".deployment-name");
        address implementation = _get("Stablecoin");

        bytes memory data = abi.encodeWithSelector(IStablecoin.initialize.selector, name, symbol);
        bytes memory args = abi.encode(implementation, data);

        proxy = _getOrDeployWithArgs(deploymentName, "ProxyWrapper", "0_8_19_opt_20000", args);

        vm.startBroadcast();

        // setup pools
        uint256 one = 10 ** IStablecoin(proxy).decimals();
        // TODO read JSON dynamic array length via something like this:
        //     uint256 poolsLength = vm.parseJsonStringArray(config, ".pools").length;
        // As of 2024-07-31, this currently fails due to https://github.com/foundry-rs/foundry/issues/8467
        uint256 POOLS_LENGTH = 3;
        for (uint256 i = 0; i < POOLS_LENGTH; i++) {
            uint256 limit = vm.parseJsonUint(config, string.concat(".pools[", vm.toString(i), "].limit"));
            uint256 threshold = vm.parseJsonUint(config, string.concat(".pools[", vm.toString(i), "].threshold"));
            uint256 signatures = vm.parseJsonUint(config, string.concat(".pools[", vm.toString(i), "].signatures"));
            IStablecoin(proxy).pushMintPool(signatures, threshold * one, limit * one);
        }

        _grantRole(IStablecoin(proxy).MINTER_ROLE(), '.roles.minter');
        _grantRole(IStablecoin(proxy).MINT_RATIFIER_ROLE(), '.roles.mint_ratifier');
        _grantRole(IStablecoin(proxy).REDEMPTION_ADMIN_ROLE(), '.roles.redemption_admin');
        _grantRole(IStablecoin(proxy).PAUSER_ROLE(), '.roles.pauser');
        _grantRole(IStablecoin(proxy).DEFAULT_ADMIN_ROLE(), '.roles.admin');

        vm.stopBroadcast();
    }

    function _get(string memory key)
    private view
    returns (address)
    {
        return enumerableDeployments.get(key).address_;
    }

    function _getOrDeployWithArgs(string memory key, string memory contractName, string memory foundryProfile, bytes memory args)
    private
    returns (address)
    {
        return enumerableDeployments.getOrDeployWithArgs(key, contractName, foundryProfile, args).address_;
    }

    function _configFile(string memory network, string memory name) private view returns (string memory) {
        return string.concat(vm.projectRoot(), "/script/configs/", network, "/", name, ".json");
    }

    function _grantRole(bytes32 role, string memory path) private {
        address[] memory addresses = vm.parseJsonAddressArray(config, path);
         for (uint256 i = 0; i < addresses.length; i++) {
            IStablecoin(proxy).grantRole(role, addresses[i]);
        }
    }
}
