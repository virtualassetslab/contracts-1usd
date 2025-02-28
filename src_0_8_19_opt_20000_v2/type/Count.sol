// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

type Count is uint256;

using {lt as <, lte as <=, eq as ==, gte as >=, gt as >} for Count global;

function lt(Count self, Count other) pure returns (bool) {
    return Count.unwrap(self) < Count.unwrap(other);
}

function lte(Count self, Count other) pure returns (bool) {
    return Count.unwrap(self) <= Count.unwrap(other);
}

function eq(Count self, Count other) pure returns (bool) {
    return Count.unwrap(self) == Count.unwrap(other);
}

function gte(Count self, Count other) pure returns (bool) {
    return Count.unwrap(self) >= Count.unwrap(other);
}

function gt(Count self, Count other) pure returns (bool) {
    return Count.unwrap(self) > Count.unwrap(other);
}
