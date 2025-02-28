// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

type Account is uint24;

using {eq as ==} for Account global;

function eq(Account self, Account other) pure returns (bool) {
    return Account.unwrap(self) == Account.unwrap(other);
}
