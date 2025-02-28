// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

type Duration is uint256;

using {eq as ==} for Duration global;

function eq(Duration self, Duration other) pure returns (bool) {
    return Duration.unwrap(self) == Duration.unwrap(other);
}
