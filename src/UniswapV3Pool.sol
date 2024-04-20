// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "./lib/Position.sol";
import "./lib/Tick.sol";

// import "./interfaces/IERC20.sol";
// import "./interfaces/IUniswapV3MintCallback.sol";
// import "./interfaces/IUniswapV3SwapCallback.sol";

/*
1. Since every pool contract is an exchange market of two tokens, we need to track the two token addresses.
2. Each pool contract is a set of liquidity positions. We’ll store them in a mapping, where keys are unique position identifiers and values are structs holding information about positions.
3. Each pool contract will also need to maintain a ticks registry–this will be a mapping with keys being tick indexes and values being structs storing information about ticks.
4. Since the tick range is limited, we need to store the limits in the contract, as constants.
5. Recall that pool contracts store the amount of liquidity, L. So we’ll need to have a variable for it.
6. Finally, we need to track the current price and the related tick. We’ll store them in one storage slot to optimize gas consumption.

참고) 저장소에서 상태변수의 레이아웃 : https://docs.soliditylang.org/en/v0.8.17/internals/layout_in_storage.html
*/
contract UniswapV3Pool {
    using Tick for mapping(int24 => Tick.Info);
    using Position for mapping(bytes32 => Position.Info);
    using Position for Position.Info;

    int24 internal constant MIN_TICK = -887272;
    int24 internal constant MAX_TICK = -MIN_TICK;

    // Pool tokens, immutable
    address public immutable token0;
    address public immutable token1;

    // Packing variables that are read together
    struct Slot0 {
        // Current sqrt(P)
        uint160 sqrtPriceX96;
        // Current tick
        int24 tick;
    }
    Slot0 public slot0;

    // Amount of liquidity, L.
    uint128 public liquidity;

    // Ticks info
    mapping(int24 => Tick.Info) public ticks;
    // Positions info
    mapping(bytes32 => Position.Info) public positions;

    constructor(
        address token0_,
        address token1_,
        uint160 sqrtPriceX96,
        int24 tick
    ) {
        token0 = token0_;
        token1 = token1_;

        slot0 = Slot0({sqrtPriceX96: sqrtPriceX96, tick: tick});
    }

    event Mint(
        address sender,
        address indexed owner,
        int24 indexed lowerTick,
        int24 indexed upperTick,
        uint128 amount,
        uint256 amount0,
        uint256 amount1
    );

    /*
    <inputs of mint function>
    1. Owner’s address, to track the owner of the liquidity.
    2. Upper and lower ticks, to set the bounds of a price range.
    3. The amount of liquidity we want to provide.

    <how mint function will work?>
    1. a user specifies a price range and an amount of liquidity.
    2. the contract updates the ticks and positions mappings.
    3. the contract calculates token amounts the user must send.
    4. the contract takes tokens from the user and verifies that the correct amounts were set.
    */
    function mint(
        address owner,
        int24 lowerTick,
        int24 upperTick,
        uint128 amount
    ) external returns (uint256 amount0, uint256 amount1) {
        if (
            lowerTick >= upperTick ||
            lowerTick < MIN_TICK ||
            upperTick > MAX_TICK
        ) revert InvalidTickRange();

        if (amount == 0) revert ZeroLiquidity();

        ticks.update(lowerTick, amount);
        ticks.update(upperTick, amount);

        Position.Info storage position = positions.get(
            owner,
            lowerTick,
            upperTick
        );
        position.update(amount);

        // we need to calculate the amounts that the user must deposit.
        amount0 = 0.998976618347425280 ether; // 임시값 하드 코딩
        amount1 = 5000 ether; // 임시값 하드 코딩

        liquidity += uint128(amount);

        uint256 balance0Before;
        uint256 balance1Before;
        if (amount0 > 0) balance0Before = balance0();
        if (amount1 > 0) balance1Before = balance1();
        IUniswapV3MintCallback(msg.sender).uniswapV3MintCallback(
            amount0,
            amount1
        );
        if (amount0 > 0 && balance0Before + amount0 > balance0())
            revert InsufficientInputAmount();
        if (amount1 > 0 && balance1Before + amount1 > balance1())
            revert InsufficientInputAmount();

        emit Mint(
            msg.sender,
            owner,
            lowerTick,
            upperTick,
            amount,
            amount0,
            amount1
        );
    }

    function balance0() internal returns (uint256 balance) {
        balance = IERC20(token0).balanceOf(address(this));
    }

    function balance1() internal returns (uint256 balance) {
        balance = IERC20(token1).balanceOf(address(this));
    }
}
