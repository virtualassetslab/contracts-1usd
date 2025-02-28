// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

type PoolIndex is uint256;

using {lt as <, gt as >, prev, next} for PoolIndex global;

function lt(PoolIndex self, PoolIndex other) pure returns (bool) {
    return PoolIndex.unwrap(self) < PoolIndex.unwrap(other);
}

function gt(PoolIndex self, PoolIndex other) pure returns (bool) {
    return PoolIndex.unwrap(self) > PoolIndex.unwrap(other);
}

function prev(PoolIndex self) pure returns (PoolIndex) {
    return PoolIndex.wrap(PoolIndex.unwrap(self) - 1);
}

function next(PoolIndex self) pure returns (PoolIndex) {
    return PoolIndex.wrap(PoolIndex.unwrap(self) + 1);
}
