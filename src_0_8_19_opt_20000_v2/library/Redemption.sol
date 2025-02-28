// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

// solhint-disable-next-line max-line-length
import {EnumerableSetUpgradeable} from "openzeppelin-contracts-upgradeable-v4.9.5/contracts/utils/structs/EnumerableSetUpgradeable.sol";

import {Account} from "../type/Account.sol";

library Redemption {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;
    using Redemption for Redemption.Params;

    struct Params {
        uint256 _min;
        EnumerableSetUpgradeable.UintSet _accounts;
        uint256[47] __gap;
    }

    error RedemptionAmountLessThanMin(uint256 amount, uint256 min);
    error RedemptionAccountForbidden(Account account);

    function min(Redemption.Params storage self) internal view returns (uint256) {
        return self._min;
    }

    function accountsLength(Redemption.Params storage self) internal view returns (uint256) {
        return self._accounts.length();
    }

    function accountAt(Redemption.Params storage self, uint256 index) internal view returns (Account) {
        return Account.wrap(uint24(self._accounts.at(index)));
    }

    function canAccountRedeem(Redemption.Params storage self, Account account) internal view returns (bool) {
        return self._accounts.contains(uint256(Account.unwrap(account)));
    }

    function checkRedemption(Redemption.Params storage self, Account account, uint256 amount) internal view {
        if (amount < self._min) {
            revert RedemptionAmountLessThanMin(amount, self._min);
        }
        if (!self.canAccountRedeem(account)) {
            revert RedemptionAccountForbidden(account);
        }
    }

    function setMin(Redemption.Params storage self, uint256 min_) internal {
        self._min = min_;
    }

    function allowAccount(Redemption.Params storage self, Account account) internal returns (bool) {
        return self._accounts.add(uint256(Account.unwrap(account)));
    }

    function forbidAccount(Redemption.Params storage self, Account account) internal returns (bool) {
        return self._accounts.remove(uint256(Account.unwrap(account)));
    }
}
