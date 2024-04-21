// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

library Position {
    struct Info {
        uint128 liquidity;
    }

    // Adds liquidity to a specific position
    function update(Info storage self, uint128 liquidityDelta) internal {
        uint128 liquidityBefore = self.liquidity;
        uint128 liquidityAfter = liquidityBefore + liquidityDelta;

        self.liquidity = liquidityAfter;
    }

    /*
    Each position is uniquely identified by three keys: owner address, lower tick index, and upper tick index.
    
    A. Why hash the three keys(owner address, lower tick index, upper tick index)?
        => to make storing data cheaper
        => 96 bytes(= 32 bytes * 3) --(hash)-> 32 bytes
        => so we just need only one mapping to store them
    */
    function get(
        mapping(bytes32 => Info) storage self,
        address owner,
        int24 lowerTick,
        int24 upperTick
    ) internal view returns (Position.Info storage position) {
        position = self[
            keccak256(abi.encodePacked(owner, lowerTick, upperTick)) // A. Why hash ~?
        ];
    }
}
