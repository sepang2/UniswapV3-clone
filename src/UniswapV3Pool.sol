// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "./interfaces/IERC20.sol";
import "./interfaces/IUniswapV3MintCallback.sol";
import "./interfaces/IUniswapV3SwapCallback.sol";

import "./lib/Position.sol";
import "./lib/Tick.sol";

/*
A. Data, the contract will store
    1) Since every pool contract is an exchange market of two tokens,
        => we need to track the two token addresses.
    2) Each pool contract is a set of liquidity positions.
        => mapping(_unique position identifier => _structs_holding_position's_information)
    3) Each pool contract will also need to maintain a ticks registry.
        => mapping(_tick_indexes => _structs_storing_tick's_information)
    4) Since the tick range is limited,
        => we need to store the limits in the contract, as constants.
    5) Recall that pool contracts store the amount of liquidity, "L". So we’ll need to have a variable for it.
    6) Finally, we need to track the current price and the related tick.
        => We’ll store them in one storage slot to optimize gas consumption.
        => https://docs.soliditylang.org/en/v0.8.17/internals/layout_in_storage.html
*/
contract UniswapV3Pool {
    using Tick for mapping(int24 => Tick.Info);
    using Position for mapping(bytes32 => Position.Info);
    using Position for Position.Info;

    error InsufficientInputAmount();
    error InvalidTickRange();
    error ZeroLiquidity();

    event Mint(
        address sender,
        address indexed owner,
        int24 indexed lowerTick,
        int24 indexed upperTick,
        uint128 amount,
        uint256 amount0,
        uint256 amount1
    );

    event Swap(
        address indexed sender,
        address indexed recipient,
        int256 amount0,
        int256 amount1,
        uint160 sqrtPriceX96,
        uint128 liquidity,
        int24 tick
    );

    // A-4) Limits of the tick
    int24 internal constant MIN_TICK = -887272;
    int24 internal constant MAX_TICK = -MIN_TICK;

    // A-1) Addresses of pool tokens, immutable
    address public immutable token0;
    address public immutable token1;

    // A-6) Packing variables(price & tick) that are read together
    // First slot will contain essential data
    struct Slot0 {
        // Current sqrt(P)
        uint160 sqrtPriceX96;
        // Current tick
        int24 tick;
    }

    struct CallbackData {
        address token0;
        address token1;
        address payer;
    }

    Slot0 public slot0;

    // A-5) Amount of liquidity, "L".
    uint128 public liquidity;

    // A-3) Ticks info
    mapping(int24 => Tick.Info) public ticks;
    // A-2) Positions info
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

    /*
    B. How mint function will work?
        1) a user specifies a price range and an amount of liquidity. (= user's input)
        2) the contract updates the ticks and positions mappings.
        3) the contract calculates token amounts the user must send.
        4) the contract takes tokens from the user and verifies that the correct amounts were set.
    */
    function mint(
        address owner, // Owner’s address, to track the owner of the liquidity.
        int24 lowerTick, // Upper and lower ticks, to set the bounds of a price range.
        int24 upperTick,
        uint128 amount, // The amount of liquidity we want to provide.
        bytes calldata data
    ) external returns (uint256 amount0, uint256 amount1) {
        // Checking range of ticks
        if (
            lowerTick >= upperTick ||
            lowerTick < MIN_TICK ||
            upperTick > MAX_TICK
        ) revert InvalidTickRange();

        // Ensuring that some amount of liquidity is provided
        if (amount == 0) revert ZeroLiquidity();

        // B-2) Update the ticks mapping
        ticks.update(lowerTick, amount);
        ticks.update(upperTick, amount);

        // B-2) Update the positions mapping
        Position.Info storage position = positions.get(
            owner,
            lowerTick,
            upperTick
        );
        position.update(amount);

        // we need to calculate the amounts that the user must deposit.
        amount0 = 0.998976618347425280 ether; // temporary hard-code. TODO: replace with calculation
        amount1 = 5000 ether; // temporary hard-code. TODO: replace with calculation

        liquidity += uint128(amount); // update the liquidity of the pool

        uint256 balance0Before;
        uint256 balance1Before;
        if (amount0 > 0) balance0Before = balance0();
        if (amount1 > 0) balance1Before = balance1();
        IUniswapV3MintCallback(msg.sender).uniswapV3MintCallback(
            amount0,
            amount1,
            data
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

    function swap(
        address recipient,
        bytes calldata data
    ) public returns (int256 amount0, int256 amount1) {
        int24 nextTick = 85184;
        uint160 nextPrice = 5604469350942327889444743441197;

        amount0 = -0.008396714242162444 ether;
        amount1 = 42 ether;

        (slot0.tick, slot0.sqrtPriceX96) = (nextTick, nextPrice);

        IERC20(token0).transfer(recipient, uint256(-amount0));

        uint256 balance1Before = balance1();
        IUniswapV3SwapCallback(msg.sender).uniswapV3SwapCallback(
            amount0,
            amount1,
            data
        );
        if (balance1Before + uint256(amount1) > balance1())
            revert InsufficientInputAmount();

        emit Swap(
            msg.sender,
            recipient,
            amount0,
            amount1,
            slot0.sqrtPriceX96,
            liquidity,
            slot0.tick
        );
    }

    ////////////////////////////////////////////////////////////////////////////
    //
    // INTERNAL
    //
    ////////////////////////////////////////////////////////////////////////////
    function balance0() internal returns (uint256 balance) {
        balance = IERC20(token0).balanceOf(address(this));
    }

    function balance1() internal returns (uint256 balance) {
        balance = IERC20(token1).balanceOf(address(this));
    }
}
