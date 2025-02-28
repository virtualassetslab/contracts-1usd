// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import {Deployments} from "forge-deploy/library/Deployments.sol";

import {Stablecoin_v2} from "../../src_0_8_19_opt_20000_v2/Stablecoin_v2.sol";

import {IProxy} from "../../src/interface/IProxy.sol";
import {IStablecoin as IStablecoin_v1, OpIndex, PoolIndex} from "../../src/interface/IStablecoin.sol";
import {IStablecoin_v2, Account as StablecoinAccount} from "../../src/interface/IStablecoin_v2.sol";

abstract contract UpgradeV2Test is Test {
    using Deployments for Deployments.EnumerableDeployments;
    Deployments.EnumerableDeployments public enumerableDeployments;

    IStablecoin_v1 public stablecoinV1Proxy;
    IStablecoin_v2 public stablecoinV2Proxy;
    Stablecoin_v2 public stablecoinV2Impl;

    address[] public defaultAdmins;
    address[] public accountAdmins;
    address[] public pausers;
    address[] public minters;
    address[] public mintRatifiers;
    address[] public frozens;
    address[] public redemptionAddresses;

    function testUpgrade() public {
        assertEq(address(stablecoinV1Proxy), address(stablecoinV2Proxy));

        assertEq(stablecoinV1Proxy.name(), "OneUSD Stablecoin");
        assertEq(stablecoinV1Proxy.symbol(), "1USD");
        assertEq(stablecoinV1Proxy.decimals(), 18);
        assertEq(stablecoinV1Proxy.viewMinimumRedemptionAmount(), 0);
        uint256 totalSupplyBefore = stablecoinV1Proxy.totalSupply();

        upgrade();

        assertEq(stablecoinV2Proxy.name(), "OneUSD Stablecoin");
        assertEq(stablecoinV2Proxy.symbol(), "1USD");
        assertEq(stablecoinV2Proxy.decimals(), 18);
        assertEq(stablecoinV2Proxy.viewMinimumRedemptionAmount(), 0);
        assertEq(stablecoinV2Proxy.viewMinimumBridgingAmount(), 0);
        uint256 totalSupplyAfter = stablecoinV2Proxy.totalSupply();

        assertEq(totalSupplyAfter, totalSupplyBefore);
    }

    function testBalanceOf() public {
        address user = address(0x123456789);

        assertEq(stablecoinV1Proxy.balanceOf(user), 0);

        uint256 amount = parseToken(100);

        vm.startPrank(minters[0]);
        stablecoinV1Proxy.requestThenFinalizeMint(user, amount, PoolIndex.wrap(0));

        assertEq(stablecoinV1Proxy.balanceOf(user), amount);

        upgrade();

        assertEq(stablecoinV2Proxy.balanceOf(user), amount);
    }

    function testRedemption() public {
        address user = address(0x123456789);

        assertEq(stablecoinV1Proxy.balanceOf(user), 0);

        uint256 amount = parseToken(100);

        vm.startPrank(minters[0]);
        stablecoinV1Proxy.requestThenFinalizeMint(user, amount, PoolIndex.wrap(0));

        vm.startPrank(user);
        stablecoinV1Proxy.transfer(redemptionAddresses[0], parseToken(25));
        assertEq(stablecoinV1Proxy.balanceOf(user), parseToken(75));

        upgrade();

        vm.startPrank(user);
        stablecoinV2Proxy.transfer(redemptionAddresses[0], parseToken(25));
        assertEq(stablecoinV2Proxy.balanceOf(user), parseToken(50));
    }

    function testDefaultAdminsDontChange() public {
        _assertV1Roles(stablecoinV1Proxy.DEFAULT_ADMIN_ROLE(), defaultAdmins);

        upgrade();

        _assertV2Roles(stablecoinV2Proxy.DEFAULT_ADMIN_ROLE(), defaultAdmins);
    }

    function testPausersDontChange() public {
        _assertV1Roles(stablecoinV1Proxy.PAUSER_ROLE(), pausers);

        upgrade();

        _assertV2Roles(stablecoinV2Proxy.PAUSER_ROLE(), pausers);
    }

    function testMintersDontChange() public {
        _assertV1Roles(stablecoinV1Proxy.MINTER_ROLE(), minters);

        upgrade();

        _assertV2Roles(stablecoinV2Proxy.MINTER_ROLE(), minters);
    }

    function testMintRatifiersDontChange() public {
        _assertV1Roles(stablecoinV1Proxy.MINT_RATIFIER_ROLE(), mintRatifiers);

        upgrade();

        _assertV2Roles(stablecoinV2Proxy.MINT_RATIFIER_ROLE(), mintRatifiers);
    }

    function testFrozensDontChange() public {
        _assertV1Roles(stablecoinV1Proxy.FROZEN_ROLE(), frozens);

        upgrade();

        _assertV2Roles(stablecoinV2Proxy.FROZEN_ROLE(), frozens);
    }

    function testRedemptionAdminsBecomeAccountAdmins() public {
        bytes32 redemptionAdminRole = stablecoinV1Proxy.REDEMPTION_ADMIN_ROLE();
        bytes32 accountAdminRole = stablecoinV2Impl.ACCOUNT_ADMIN_ROLE();

        _assertV1Roles(redemptionAdminRole, accountAdmins);
        _assertV1Roles(accountAdminRole, new address[](0));

        upgrade();

        _assertV2Roles(redemptionAdminRole, new address[](0));
        _assertV2Roles(accountAdminRole, accountAdmins);
    }

    function testClearsAdminRoleForRedemptionAddressRole() public {
        bytes32 redemptionAddressRole = stablecoinV1Proxy.REDEMPTION_ADDRESS_ROLE();

        assertEq(stablecoinV1Proxy.getRoleAdmin(redemptionAddressRole), stablecoinV1Proxy.REDEMPTION_ADMIN_ROLE());

        upgrade();

        assertEq(stablecoinV2Proxy.getRoleAdmin(redemptionAddressRole), stablecoinV2Proxy.DEFAULT_ADMIN_ROLE());
    }

    function testRedemptionAddressesBecomeAccountsThatCanRedeem() public {
        bytes32 redemptionAddressRole = stablecoinV1Proxy.REDEMPTION_ADDRESS_ROLE();

        _assertV1Roles(redemptionAddressRole, redemptionAddresses);

        upgrade();

        _assertV2Roles(redemptionAddressRole, new address[](0));

        assertEq(stablecoinV2Proxy.viewRedemptionAccountsCount(), redemptionAddresses.length);
        for (uint256 i; i < redemptionAddresses.length; i++) {
            StablecoinAccount account = StablecoinAccount.wrap(uint24(uint160(redemptionAddresses[i])));
            assertEq(stablecoinV2Proxy.canAccountRedeem(account), true);
        }
    }

    function upgrade() internal virtual {}

    function _assertV1Roles(bytes32 role, address[] memory addresses) internal view {
        assertEq(stablecoinV1Proxy.getRoleMemberCount(role), addresses.length);
        for (uint256 i; i < addresses.length; i++) {
            assertEq(stablecoinV1Proxy.hasRole(role, addresses[i]), true);
        }
    }

    function _assertV2Roles(bytes32 role, address[] memory addresses) internal view {
        assertEq(stablecoinV2Proxy.getRoleMemberCount(role), addresses.length);
        for (uint256 i; i < addresses.length; i++) {
            assertEq(stablecoinV2Proxy.hasRole(role, addresses[i]), true);
        }
    }

    function _get(string memory key) public view returns (address) {
        return enumerableDeployments.get(key).address_;
    }

    function parseToken(uint256 value) public view returns (uint256) {
        return value * (10 ** stablecoinV2Proxy.decimals());
    }
}
