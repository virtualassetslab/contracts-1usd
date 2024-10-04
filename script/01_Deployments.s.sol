// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {Deployments} from "forge-deploy/library/Deployments.sol";

contract DeploymentsScript is Script {
    using Deployments for Deployments.EnumerableDeployments;

    Deployments.EnumerableDeployments enumerableDeployments;

    function run(string memory network) public {
        vm.createSelectFork(network);
        enumerableDeployments.hydrate(network);

        _getOrDeploy("Stablecoin", "out/Stablecoin.sol/Stablecoin.json", "0_8_19_opt_20000");
    }

    function _getOrDeploy(string memory key, string memory artifactPath, string memory foundryProfile)
    private
    returns (address)
    {
        return enumerableDeployments.getOrDeploy(key, artifactPath, foundryProfile).address_;
    }
}
