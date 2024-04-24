// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import "@openzeppelin/contracts/access/Ownable.sol";

contract RateLimiter is Ownable {
    struct RateLimit {
        int128 lastValue;
        uint128 limit;
        uint256 interval;
    }

    address public bridgeHandler;
    mapping(bytes32 => RateLimit[]) public rateLimits;
    mapping(bytes32 => uint256) public lastUpdates;

    event LimitAdded(bytes32 indexed resourceId, uint256 indexed index, uint128 limit, uint256 interval);
    event LimitUpdated(bytes32 indexed resourceId, uint256 indexed index, uint128 limit, uint256 interval);
    event LimitRemoved(bytes32 indexed resourceId, uint256 indexed index);

    modifier onlyBridgeHandler() {
        require(msg.sender == bridgeHandler);
        _;
    }

    constructor(address _bridgeHandler) {
        bridgeHandler = _bridgeHandler;
    }

    function getNumLimits(bytes32 resourceId) external view returns (uint256) {
        return rateLimits[resourceId].length;
    }

    function addLimit(bytes32 resourceId, uint128 limit, uint256 interval) external onlyOwner {
        rateLimits[resourceId].push(RateLimit(0, limit, interval));

        emit LimitAdded(resourceId, rateLimits[resourceId].length - 1, limit, interval);
    }

    function updateLimit(bytes32 resourceId, uint256 index, uint128 limit, uint256 interval) external onlyOwner {
        RateLimit memory rateLimit = rateLimits[resourceId][index];
        rateLimit.limit = limit;
        rateLimit.interval = interval;
        rateLimits[resourceId][index] = rateLimit;

        emit LimitUpdated(resourceId, index, limit, interval);
    }

    function removeLimit(bytes32 resourceId, uint256 index) external onlyOwner {
        rateLimits[resourceId][index] = RateLimit(0, 0, 0);
        emit LimitRemoved(resourceId, index);
    }

    function update(bytes32 resourceId, int256 amount) external onlyBridgeHandler {
        uint256 timestamp = block.timestamp;
        for (uint256 i = 0; i < rateLimits[resourceId].length; i++) {
            RateLimit memory rateLimit = rateLimits[resourceId][i];
            if (rateLimit.interval == 0) continue;

            int256 lastValue = rateLimit.lastValue;
            if (rateLimit.lastValue != 0) {
                // decrement lastValue for passed time since last update
                int256 decreaseBy = (lastValue * int256(timestamp - lastUpdates[resourceId])) /
                    int256(rateLimit.interval);

                if (lastValue > 0 ? decreaseBy >= lastValue : decreaseBy <= lastValue) {
                    lastValue = 0;
                } else {
                    lastValue -= decreaseBy;
                }
            }

            // add amount to lastValue and check constraints
            lastValue += amount;
            int256 limit = int256(uint256(rateLimit.limit));
            require(limit >= lastValue && lastValue >= -limit, "Rate Limit");

            // save new value
            rateLimits[resourceId][i].lastValue = int128(lastValue);
        }
        lastUpdates[resourceId] = timestamp;
    }
}
