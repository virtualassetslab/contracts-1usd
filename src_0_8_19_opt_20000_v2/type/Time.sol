// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Duration} from "./Duration.sol";

type Time is uint256;

using {lt as <, gt as >, add} for Time global;

function lt(Time self, Time other) pure returns (bool) {
    return Time.unwrap(self) < Time.unwrap(other);
}

function gt(Time self, Time other) pure returns (bool) {
    return Time.unwrap(self) > Time.unwrap(other);
}

function add(Time self, Duration other) pure returns (Time) {
    return Time.wrap(Time.unwrap(self) + Duration.unwrap(other));
}
