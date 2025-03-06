// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Deployments} from "forge-deploy/library/Deployments.sol";

import {Stablecoin_v2} from "../src_0_8_19_opt_20000_v2/Stablecoin_v2.sol";

import {IProxy} from "../src/interface/IProxy.sol";
import {IStablecoin as IStablecoin_v1} from "../src/interface/IStablecoin.sol";
import {IStablecoin_v2} from "../src/interface/IStablecoin_v2.sol";

import {UpgradeV2Test} from "./abstract/UpgradeV2.t.sol";

contract UpgradeV2Test_Mainnet is UpgradeV2Test {
    using Deployments for Deployments.EnumerableDeployments;

    function setUp() public {
        // TODO Fork just before the successful upgrade at this tx hash
        vm.createSelectFork("mainnet");
        enumerableDeployments.hydrate("mainnet");

        // cannot use _get() - not deployed to mainnet yet
        stablecoinV2Impl = new Stablecoin_v2();

        stablecoinV1Proxy = IStablecoin_v1(_get("1USD_Stablecoin"));
        stablecoinV2Proxy = IStablecoin_v2(address(stablecoinV1Proxy));

        tokenName = "OneUSD Stablecoin";

        defaultAdmins = [0x16cEa306506c387713C70b9C1205fd5aC997E78E];
        mintRatifiers = [
            0x0D55E17ca63ffF2715859528EddC54D0A7E91248,
            0x80bA50157eEa3d33E179E7C50C1f3D59484B1790,
            0x083B59F244f8BAcbc79282Cdd623686324C962AC,
            0x960b1d99A841399fB226715d9eF8cCAfb9996bC8,
            0xFbF329794a64Bf940f7B3bdaFf4F2157ba23B3CC,
            0x937c8C2d78fd98E6C5488519B05a797ae1b9Eb40,
            0x330Aaf998c9D2Fe97D1ab86Da724daF2F4d032E7
        ];
        pausers = [0xf0aE09d3ABdF3641e2eB4cD45cf56873296a02CB];
        accountAdmins = [0xb491aDC64216D4B48a4400c547f826389cB1b6F6];
        minters = [0x6a5f2d9d372D91D372dD4fD19171a04fB1FeB453];

        redemptionAddresses = [0x0000000000000000000000000000000000003077];

        frozens = new address[](0);
    }

    function upgrade() internal override {
        vm.startPrank(defaultAdmins[0]);
        IProxy(address(stablecoinV1Proxy)).upgradeToAndCall(
            address(stablecoinV2Impl),
            abi.encodeWithSelector(stablecoinV2Impl.initializeV2.selector)
        );
        vm.stopPrank();
    }
}
