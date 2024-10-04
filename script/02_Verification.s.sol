// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {Deployments} from "forge-deploy/library/Deployments.sol";

contract VerificationScript is Script {
    using Deployments for Deployments.EnumerableDeployments;

    Deployments.EnumerableDeployments enumerableDeployments;

    function run(string memory network) public {
        vm.createSelectFork(network);
        enumerableDeployments.hydrate(network);

        for (uint256 i = 0; i < enumerableDeployments.length(); i++) {
            enumerableDeployments.verify(enumerableDeployments.keyAt(i));
        }
    }
}
