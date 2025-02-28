// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

type Chain is uint8;

using {eq as ==} for Chain global;

function eq(Chain self, Chain other) pure returns (bool) {
    return Chain.unwrap(self) == Chain.unwrap(other);
}
