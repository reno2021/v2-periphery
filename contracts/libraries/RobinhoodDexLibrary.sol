// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.12;

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';

import './SafeMath.sol';

library RobinhoodDexLibrary {
    using SafeMath for uint256;

    uint256 internal constant BPS_DENOMINATOR = 10000;
    uint256 internal constant PROTOCOL_FEE_BPS = 120;
    uint256 internal constant CORE_SWAP_FEE_NUMERATOR = 997;
    uint256 internal constant CORE_SWAP_FEE_DENOMINATOR = 1000;

    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, 'RobinhoodDexLibrary: IDENTICAL_ADDRESSES');
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'RobinhoodDexLibrary: ZERO_ADDRESS');
    }

    function pairFor(address factory, address tokenA, address tokenB) internal view returns (address pair) {
        pair = IUniswapV2Factory(factory).getPair(tokenA, tokenB);
        require(pair != address(0), 'RobinhoodDexLibrary: PAIR_NOT_FOUND');
    }

    function getReserves(address factory, address tokenA, address tokenB) internal view returns (uint256 reserveA, uint256 reserveB) {
        (address token0,) = sortTokens(tokenA, tokenB);
        (uint256 reserve0, uint256 reserve1,) = IUniswapV2Pair(pairFor(factory, tokenA, tokenB)).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) internal pure returns (uint256 amountB) {
        require(amountA > 0, 'RobinhoodDexLibrary: INSUFFICIENT_AMOUNT');
        require(reserveA > 0 && reserveB > 0, 'RobinhoodDexLibrary: INSUFFICIENT_LIQUIDITY');
        amountB = amountA.mul(reserveB) / reserveA;
    }

    function protocolFeeAmountFromTotal(uint256 totalAmount) internal pure returns (uint256 feeAmount) {
        feeAmount = totalAmount.mul(PROTOCOL_FEE_BPS) / BPS_DENOMINATOR;
    }

    function amountAfterProtocolFee(uint256 totalAmount) internal pure returns (uint256 netAmount) {
        netAmount = totalAmount.sub(protocolFeeAmountFromTotal(totalAmount));
    }

    function grossUpAmount(uint256 netAmount) internal pure returns (uint256 grossAmount) {
        if (netAmount == 0) {
            return 0;
        }
        grossAmount = netAmount.mul(BPS_DENOMINATOR).add(BPS_DENOMINATOR - PROTOCOL_FEE_BPS - 1) /
            (BPS_DENOMINATOR - PROTOCOL_FEE_BPS);
    }

    function getAmountOutFromPairInput(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256 amountOut) {
        require(amountIn > 0, 'RobinhoodDexLibrary: INSUFFICIENT_INPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'RobinhoodDexLibrary: INSUFFICIENT_LIQUIDITY');
        uint256 amountInWithFee = amountIn.mul(CORE_SWAP_FEE_NUMERATOR);
        uint256 numerator = amountInWithFee.mul(reserveOut);
        uint256 denominator = reserveIn.mul(CORE_SWAP_FEE_DENOMINATOR).add(amountInWithFee);
        amountOut = numerator / denominator;
    }

    function getAmountInForPairOutput(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256 amountIn) {
        require(amountOut > 0, 'RobinhoodDexLibrary: INSUFFICIENT_OUTPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'RobinhoodDexLibrary: INSUFFICIENT_LIQUIDITY');
        uint256 numerator = reserveIn.mul(amountOut).mul(CORE_SWAP_FEE_DENOMINATOR);
        uint256 denominator = reserveOut.sub(amountOut).mul(CORE_SWAP_FEE_NUMERATOR);
        amountIn = numerator / denominator + 1;
    }

    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256 amountOut) {
        amountOut = getAmountOutFromPairInput(amountAfterProtocolFee(amountIn), reserveIn, reserveOut);
    }

    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256 amountIn) {
        amountIn = grossUpAmount(getAmountInForPairOutput(amountOut, reserveIn, reserveOut));
    }

    function getAmountsOutFromPairInput(address factory, uint256 pairAmountIn, address[] memory path)
        internal
        view
        returns (uint256[] memory amounts)
    {
        require(path.length >= 2, 'RobinhoodDexLibrary: INVALID_PATH');
        amounts = new uint256[](path.length);
        amounts[0] = pairAmountIn;
        for (uint256 i; i < path.length - 1; i++) {
            (uint256 reserveIn, uint256 reserveOut) = getReserves(factory, path[i], path[i + 1]);
            amounts[i + 1] = getAmountOutFromPairInput(amounts[i], reserveIn, reserveOut);
        }
    }

    function getAmountsOut(address factory, uint256 amountIn, address[] memory path)
        internal
        view
        returns (uint256[] memory amounts)
    {
        amounts = getAmountsOutFromPairInput(factory, amountAfterProtocolFee(amountIn), path);
        amounts[0] = amountIn;
    }

    function getAmountsInForPairOutput(address factory, uint256 amountOut, address[] memory path)
        internal
        view
        returns (uint256[] memory amounts)
    {
        require(path.length >= 2, 'RobinhoodDexLibrary: INVALID_PATH');
        amounts = new uint256[](path.length);
        amounts[amounts.length - 1] = amountOut;
        for (uint256 i = path.length - 1; i > 0; i--) {
            (uint256 reserveIn, uint256 reserveOut) = getReserves(factory, path[i - 1], path[i]);
            amounts[i - 1] = getAmountInForPairOutput(amounts[i], reserveIn, reserveOut);
        }
    }

    function getAmountsIn(address factory, uint256 amountOut, address[] memory path)
        internal
        view
        returns (uint256[] memory amounts)
    {
        amounts = getAmountsInForPairOutput(factory, amountOut, path);
        amounts[0] = grossUpAmount(amounts[0]);
    }
}
