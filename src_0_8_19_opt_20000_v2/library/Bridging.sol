// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

// solhint-disable-next-line max-line-length
import {EnumerableSetUpgradeable} from "openzeppelin-contracts-upgradeable-v4.9.5/contracts/utils/structs/EnumerableSetUpgradeable.sol";

import {Account} from "../type/Account.sol";
import {Chain} from "../type/Chain.sol";

library Bridging {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;
    using Bridging for Bridging.Params;

    struct Params {
        uint256 _min;
        EnumerableSetUpgradeable.UintSet _chains;
        EnumerableSetUpgradeable.UintSet _accounts;
        uint256[45] __gap;
    }

    error BridgingAmountLessThanMin(uint256 amount, uint256 min);
    error BridgingChainForbidden(Chain chain);
    error BridgingAccountForbidden(Account account);

    function min(Bridging.Params storage self) internal view returns (uint256) {
        return self._min;
    }

    function chainsLength(Bridging.Params storage self) internal view returns (uint256) {
        return self._chains.length();
    }

    function chainAt(Bridging.Params storage self, uint256 index) internal view returns (Chain) {
        return Chain.wrap(uint8(self._chains.at(index)));
    }

    function canBridgeToChain(Bridging.Params storage self, Chain chain) internal view returns (bool) {
        return self._chains.contains(uint256(Chain.unwrap(chain)));
    }

    function accountsLength(Bridging.Params storage self) internal view returns (uint256) {
        return self._accounts.length();
    }

    function accountAt(Bridging.Params storage self, uint256 index) internal view returns (Account) {
        return Account.wrap(uint24(self._accounts.at(index)));
    }

    function canAccountBridge(Bridging.Params storage self, Account account) internal view returns (bool) {
        return self._accounts.contains(uint256(Account.unwrap(account)));
    }

    function checkBridging(Bridging.Params storage self, Chain chain, Account account, uint256 amount) internal view {
        if (amount < self._min) {
            revert BridgingAmountLessThanMin(amount, self._min);
        }
        if (!self.canBridgeToChain(chain)) {
            revert BridgingChainForbidden(chain);
        }
        if (!self.canAccountBridge(account)) {
            revert BridgingAccountForbidden(account);
        }
    }

    function setMin(Bridging.Params storage self, uint256 min_) internal {
        self._min = min_;
    }

    function allowChain(Bridging.Params storage self, Chain chain) internal returns (bool) {
        return self._chains.add(uint256(Chain.unwrap(chain)));
    }

    function forbidChain(Bridging.Params storage self, Chain chain) internal returns (bool) {
        return self._chains.remove(uint256(Chain.unwrap(chain)));
    }

    function allowAccount(Bridging.Params storage self, Account account) internal returns (bool) {
        return self._accounts.add(uint256(Account.unwrap(account)));
    }

    function forbidAccount(Bridging.Params storage self, Account account) internal returns (bool) {
        return self._accounts.remove(uint256(Account.unwrap(account)));
    }
}
