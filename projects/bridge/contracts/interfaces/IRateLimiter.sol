// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

interface IRateLimiter {
    function update(bytes32 resourceId, int256 amount) external;
}
