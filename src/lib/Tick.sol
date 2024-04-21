// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

library Tick {
    struct Info {
        bool initialized;
        uint128 liquidity;
    }

    // Adds liquidity to specific tick
    // This function is called by both lower and upper ticks.
    function update(
        mapping(int24 => Tick.Info) storage self,
        int24 tick,
        uint128 liquidityDelta
    ) internal {
        Tick.Info storage tickInfo = self[tick];
        uint128 liquidityBefore = tickInfo.liquidity;
        uint128 liquidityAfter = liquidityBefore + liquidityDelta;

        // Initializes a tick if it has 0 liquidity and adds new liquidity
        if (liquidityBefore == 0) {
            tickInfo.initialized = true;
        }

        tickInfo.liquidity = liquidityAfter;
    }
}
