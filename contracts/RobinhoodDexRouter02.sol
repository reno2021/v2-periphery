// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.12;

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';

import './interfaces/IUniswapV2Router02.sol';
import './interfaces/IERC20.sol';
import './interfaces/IWETH.sol';
import './libraries/RobinhoodDexLibrary.sol';
import './libraries/SafeMath.sol';
import './libraries/TransferHelper.sol';

contract RobinhoodDexRouter02 is IUniswapV2Router02 {
    using SafeMath for uint256;

    uint256 public constant BPS_DENOMINATOR = 10000;
    uint256 public constant PROTOCOL_FEE_BPS = 120;
    uint256 public constant REWARDS_FEE_BPS = 90;
    uint256 public constant DEVELOPMENT_FEE_BPS = 30;
    uint8 private constant ACTION_SWAP = 0;
    uint8 private constant ACTION_ADD_LIQUIDITY = 1;
    uint8 private constant ACTION_REMOVE_LIQUIDITY = 2;

    address public immutable override factory;
    address public immutable override WETH;
    address public immutable protocolFeeRecipient;

    event ProtocolFeeCollected(
        address indexed payer,
        address indexed feeToken,
        uint256 grossAmount,
        uint256 feeAmount,
        uint8 indexed actionType
    );

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, 'RobinhoodDexRouter: EXPIRED');
        _;
    }

    constructor(
        address factory_,
        address weth_,
        address protocolFeeRecipient_
    ) public {
        require(factory_ != address(0), 'RobinhoodDexRouter: ZERO_FACTORY');
        require(weth_ != address(0), 'RobinhoodDexRouter: ZERO_WETH');
        require(protocolFeeRecipient_ != address(0), 'RobinhoodDexRouter: ZERO_RECIPIENT');
        factory = factory_;
        WETH = weth_;
        protocolFeeRecipient = protocolFeeRecipient_;
    }

    receive() external payable {
        require(msg.sender == WETH, 'RobinhoodDexRouter: ETH_NOT_ALLOWED');
    }

    function feeBreakdown() external pure returns (uint256 rewardsFeeBps, uint256 developmentFeeBps, uint256 totalFeeBps) {
        return (REWARDS_FEE_BPS, DEVELOPMENT_FEE_BPS, PROTOCOL_FEE_BPS);
    }

    function _createPairIfNeeded(address tokenA, address tokenB) internal returns (address pair) {
        pair = IUniswapV2Factory(factory).getPair(tokenA, tokenB);
        if (pair == address(0)) {
            pair = IUniswapV2Factory(factory).createPair(tokenA, tokenB);
        }
    }

    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) internal returns (uint256 amountA, uint256 amountB) {
        _createPairIfNeeded(tokenA, tokenB);
        (uint256 reserveA, uint256 reserveB) = RobinhoodDexLibrary.getReserves(factory, tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint256 amountBOptimal = RobinhoodDexLibrary.quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, 'RobinhoodDexRouter: INSUFFICIENT_B_AMOUNT');
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = RobinhoodDexLibrary.quote(amountBDesired, reserveB, reserveA);
                require(amountAOptimal <= amountADesired, 'RobinhoodDexRouter: EXCESSIVE_A_AMOUNT');
                require(amountAOptimal >= amountAMin, 'RobinhoodDexRouter: INSUFFICIENT_A_AMOUNT');
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
        require(amountA >= amountAMin, 'RobinhoodDexRouter: INSUFFICIENT_A_AMOUNT');
        require(amountB >= amountBMin, 'RobinhoodDexRouter: INSUFFICIENT_B_AMOUNT');
    }

    function _emitProtocolFee(address payer, address feeToken, uint256 grossAmount, uint256 feeAmount, uint8 actionType) internal {
        if (feeAmount > 0) {
            emit ProtocolFeeCollected(payer, feeToken, grossAmount, feeAmount, actionType);
        }
    }

    function _collectTokenWithKnownPairAmount(
        address token,
        address pair,
        uint256 pairAmount,
        uint8 actionType
    ) internal returns (uint256 grossAmount, uint256 feeAmount) {
        grossAmount = RobinhoodDexLibrary.grossUpAmount(pairAmount);
        feeAmount = grossAmount.sub(pairAmount);
        if (feeAmount > 0) {
            TransferHelper.safeTransferFrom(token, msg.sender, protocolFeeRecipient, feeAmount);
            _emitProtocolFee(msg.sender, token, grossAmount, feeAmount, actionType);
        }
        if (pairAmount > 0) {
            TransferHelper.safeTransferFrom(token, msg.sender, pair, pairAmount);
        }
    }

    function _collectTokenWithKnownGrossAmount(
        address token,
        address pair,
        uint256 grossAmount,
        uint8 actionType
    ) internal returns (uint256 pairAmount, uint256 feeAmount) {
        feeAmount = RobinhoodDexLibrary.protocolFeeAmountFromTotal(grossAmount);
        pairAmount = grossAmount.sub(feeAmount);
        if (feeAmount > 0) {
            TransferHelper.safeTransferFrom(token, msg.sender, protocolFeeRecipient, feeAmount);
            _emitProtocolFee(msg.sender, token, grossAmount, feeAmount, actionType);
        }
        if (pairAmount > 0) {
            TransferHelper.safeTransferFrom(token, msg.sender, pair, pairAmount);
        }
    }

    function _swap(uint256[] memory amounts, address[] memory path, address _to) internal {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = RobinhoodDexLibrary.sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) = input == token0 ? (uint256(0), amountOut) : (amountOut, uint256(0));
            address to = i < path.length - 2 ? RobinhoodDexLibrary.pairFor(factory, output, path[i + 2]) : _to;
            IUniswapV2Pair(RobinhoodDexLibrary.pairFor(factory, input, output)).swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }

    function _transferRouterHeldTokenWithFee(
        address token,
        address to,
        uint256 grossAmount,
        uint256 minAmount
    ) internal returns (uint256 netAmount) {
        uint256 feeAmount = RobinhoodDexLibrary.protocolFeeAmountFromTotal(grossAmount);
        netAmount = grossAmount.sub(feeAmount);
        require(netAmount >= minAmount, 'RobinhoodDexRouter: INSUFFICIENT_TOKEN_AMOUNT');
        if (feeAmount > 0) {
            TransferHelper.safeTransfer(token, protocolFeeRecipient, feeAmount);
            _emitProtocolFee(msg.sender, token, grossAmount, feeAmount, ACTION_REMOVE_LIQUIDITY);
        }
        TransferHelper.safeTransfer(token, to, netAmount);
    }

    function _withdrawRouterHeldWETHWithFee(
        address to,
        uint256 grossWethAmount,
        uint256 minAmount
    ) internal returns (uint256 netAmount) {
        uint256 feeAmount = RobinhoodDexLibrary.protocolFeeAmountFromTotal(grossWethAmount);
        netAmount = grossWethAmount.sub(feeAmount);
        require(netAmount >= minAmount, 'RobinhoodDexRouter: INSUFFICIENT_ETH_AMOUNT');
        IWETH(WETH).withdraw(grossWethAmount);
        if (feeAmount > 0) {
            TransferHelper.safeTransferETH(protocolFeeRecipient, feeAmount);
            _emitProtocolFee(msg.sender, address(0), grossWethAmount, feeAmount, ACTION_REMOVE_LIQUIDITY);
        }
        TransferHelper.safeTransferETH(to, netAmount);
    }

    function _transferRouterHeldTokenWithFeeAndCheckRecipient(
        address token,
        address to,
        uint256 grossAmount,
        uint256 minRecipientAmount
    ) internal {
        uint256 recipientBalanceBefore = IERC20(token).balanceOf(to);
        _transferRouterHeldTokenWithFee(token, to, grossAmount, 0);
        require(
            IERC20(token).balanceOf(to).sub(recipientBalanceBefore) >= minRecipientAmount,
            'RobinhoodDexRouter: INSUFFICIENT_TOKEN_AMOUNT'
        );
    }

    function _burnPairToRouter(
        address pair,
        address tokenA,
        address tokenB
    ) internal returns (uint256 grossAmountA, uint256 grossAmountB) {
        (uint256 amount0, uint256 amount1) = IUniswapV2Pair(pair).burn(address(this));
        (address token0,) = RobinhoodDexLibrary.sortTokens(tokenA, tokenB);
        (grossAmountA, grossAmountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
    }

    function _pullAndBurnLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity
    ) internal returns (uint256 grossAmountA, uint256 grossAmountB) {
        address pair = RobinhoodDexLibrary.pairFor(factory, tokenA, tokenB);
        IUniswapV2Pair(pair).transferFrom(msg.sender, pair, liquidity);
        (grossAmountA, grossAmountB) = _burnPairToRouter(pair, tokenA, tokenB);
    }

    function _collectAddLiquidityTokens(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB
    ) internal returns (address pair) {
        pair = RobinhoodDexLibrary.pairFor(factory, tokenA, tokenB);
        _collectTokenWithKnownPairAmount(tokenA, pair, amountA, ACTION_ADD_LIQUIDITY);
        _collectTokenWithKnownPairAmount(tokenB, pair, amountB, ACTION_ADD_LIQUIDITY);
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external override ensure(deadline) returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        uint256 netDesiredA = RobinhoodDexLibrary.amountAfterProtocolFee(amountADesired);
        uint256 netDesiredB = RobinhoodDexLibrary.amountAfterProtocolFee(amountBDesired);
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, netDesiredA, netDesiredB, amountAMin, amountBMin);
        address pair = _collectAddLiquidityTokens(tokenA, tokenB, amountA, amountB);
        liquidity = IUniswapV2Pair(pair).mint(to);
    }

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable override ensure(deadline) returns (uint256 amountToken, uint256 amountETH, uint256 liquidity) {
        uint256 netTokenDesired = RobinhoodDexLibrary.amountAfterProtocolFee(amountTokenDesired);
        uint256 netEthDesired = RobinhoodDexLibrary.amountAfterProtocolFee(msg.value);
        (amountToken, amountETH) = _addLiquidity(token, WETH, netTokenDesired, netEthDesired, amountTokenMin, amountETHMin);
        address pair = RobinhoodDexLibrary.pairFor(factory, token, WETH);
        _collectTokenWithKnownPairAmount(token, pair, amountToken, ACTION_ADD_LIQUIDITY);

        uint256 grossETHAmount = RobinhoodDexLibrary.grossUpAmount(amountETH);
        require(msg.value >= grossETHAmount, 'RobinhoodDexRouter: INSUFFICIENT_ETH_SENT');
        uint256 ethFee = grossETHAmount.sub(amountETH);
        if (ethFee > 0) {
            TransferHelper.safeTransferETH(protocolFeeRecipient, ethFee);
            _emitProtocolFee(msg.sender, address(0), grossETHAmount, ethFee, ACTION_ADD_LIQUIDITY);
        }
        IWETH(WETH).deposit{value: amountETH}();
        require(IWETH(WETH).transfer(pair, amountETH), 'RobinhoodDexRouter: WETH_TRANSFER_FAILED');
        liquidity = IUniswapV2Pair(pair).mint(to);
        if (msg.value > grossETHAmount) {
            TransferHelper.safeTransferETH(msg.sender, msg.value.sub(grossETHAmount));
        }
    }

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) public override ensure(deadline) returns (uint256 amountA, uint256 amountB) {
        (uint256 grossAmountA, uint256 grossAmountB) = _pullAndBurnLiquidity(tokenA, tokenB, liquidity);
        amountA = _transferRouterHeldTokenWithFee(tokenA, to, grossAmountA, amountAMin);
        amountB = _transferRouterHeldTokenWithFee(tokenB, to, grossAmountB, amountBMin);
    }

    function removeLiquidityETH(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) public override ensure(deadline) returns (uint256 amountToken, uint256 amountETH) {
        (uint256 grossTokenAmount, uint256 grossWethAmount) = _pullAndBurnLiquidity(token, WETH, liquidity);
        amountToken = _transferRouterHeldTokenWithFee(token, to, grossTokenAmount, amountTokenMin);
        amountETH = _withdrawRouterHeldWETHWithFee(to, grossWethAmount, amountETHMin);
    }

    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override returns (uint256 amountA, uint256 amountB) {
        address pair = RobinhoodDexLibrary.pairFor(factory, tokenA, tokenB);
        uint256 value = approveMax ? uint256(-1) : liquidity;
        IUniswapV2Pair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountA, amountB) = removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline);
    }

    function removeLiquidityETHWithPermit(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override returns (uint256 amountToken, uint256 amountETH) {
        address pair = RobinhoodDexLibrary.pairFor(factory, token, WETH);
        uint256 value = approveMax ? uint256(-1) : liquidity;
        IUniswapV2Pair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountToken, amountETH) = removeLiquidityETH(token, liquidity, amountTokenMin, amountETHMin, to, deadline);
    }

    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) public override ensure(deadline) returns (uint256 amountETH) {
        address pair = RobinhoodDexLibrary.pairFor(factory, token, WETH);
        uint256 tokenBalanceBefore = IERC20(token).balanceOf(address(this));
        uint256 wethBalanceBefore = IERC20(WETH).balanceOf(address(this));
        IUniswapV2Pair(pair).transferFrom(msg.sender, pair, liquidity);
        IUniswapV2Pair(pair).burn(address(this));
        uint256 grossTokenAmount = IERC20(token).balanceOf(address(this)).sub(tokenBalanceBefore);
        uint256 grossWethAmount = IERC20(WETH).balanceOf(address(this)).sub(wethBalanceBefore);
        _transferRouterHeldTokenWithFeeAndCheckRecipient(token, to, grossTokenAmount, amountTokenMin);
        amountETH = _withdrawRouterHeldWETHWithFee(to, grossWethAmount, amountETHMin);
    }

    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override returns (uint256 amountETH) {
        address pair = RobinhoodDexLibrary.pairFor(factory, token, WETH);
        uint256 value = approveMax ? uint256(-1) : liquidity;
        IUniswapV2Pair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        amountETH = removeLiquidityETHSupportingFeeOnTransferTokens(token, liquidity, amountTokenMin, amountETHMin, to, deadline);
    }

    function _swapSupportingFeeOnTransferTokens(address[] memory path, address _to) internal {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = RobinhoodDexLibrary.sortTokens(input, output);
            IUniswapV2Pair pair = IUniswapV2Pair(RobinhoodDexLibrary.pairFor(factory, input, output));
            uint256 amountInput;
            uint256 amountOutput;
            {
                (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
                (uint256 reserveInput, uint256 reserveOutput) = input == token0 ? (uint256(reserve0), uint256(reserve1)) : (uint256(reserve1), uint256(reserve0));
                amountInput = IERC20(input).balanceOf(address(pair)).sub(reserveInput);
                amountOutput = RobinhoodDexLibrary.getAmountOutFromPairInput(amountInput, reserveInput, reserveOutput);
            }
            (uint256 amount0Out, uint256 amount1Out) = input == token0 ? (uint256(0), amountOutput) : (amountOutput, uint256(0));
            address to = i < path.length - 2 ? RobinhoodDexLibrary.pairFor(factory, output, path[i + 2]) : _to;
            pair.swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }

    function _validatePathLength(address[] memory path) internal pure {
        require(path.length >= 2, 'RobinhoodDexRouter: INVALID_PATH');
    }

    function _validateSupportingFeeOnTransferRecipient(address[] memory path, address to) internal view {
        for (uint256 i; i < path.length; i++) {
            require(to != path[i], 'RobinhoodDexRouter: INVALID_TO');
        }
        for (uint256 i; i < path.length - 1; i++) {
            require(to != RobinhoodDexLibrary.pairFor(factory, path[i], path[i + 1]), 'RobinhoodDexRouter: INVALID_TO');
        }
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external override ensure(deadline) returns (uint256[] memory amounts) {
        _validatePathLength(path);
        uint256 pairAmountIn = RobinhoodDexLibrary.amountAfterProtocolFee(amountIn);
        uint256[] memory pairAmounts = RobinhoodDexLibrary.getAmountsOutFromPairInput(factory, pairAmountIn, path);
        require(pairAmounts[pairAmounts.length - 1] >= amountOutMin, 'RobinhoodDexRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        _collectTokenWithKnownGrossAmount(path[0], RobinhoodDexLibrary.pairFor(factory, path[0], path[1]), amountIn, ACTION_SWAP);
        _swap(pairAmounts, path, to);
        amounts = pairAmounts;
        amounts[0] = amountIn;
    }

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external override ensure(deadline) returns (uint256[] memory amounts) {
        _validatePathLength(path);
        uint256[] memory pairAmounts = RobinhoodDexLibrary.getAmountsInForPairOutput(factory, amountOut, path);
        uint256 grossAmountIn = RobinhoodDexLibrary.grossUpAmount(pairAmounts[0]);
        require(grossAmountIn <= amountInMax, 'RobinhoodDexRouter: EXCESSIVE_INPUT_AMOUNT');
        _collectTokenWithKnownPairAmount(path[0], RobinhoodDexLibrary.pairFor(factory, path[0], path[1]), pairAmounts[0], ACTION_SWAP);
        _swap(pairAmounts, path, to);
        amounts = pairAmounts;
        amounts[0] = grossAmountIn;
    }

    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable override ensure(deadline) returns (uint256[] memory amounts) {
        _validatePathLength(path);
        require(path[0] == WETH, 'RobinhoodDexRouter: INVALID_PATH');
        uint256 pairAmountIn = RobinhoodDexLibrary.amountAfterProtocolFee(msg.value);
        uint256 ethFee = msg.value.sub(pairAmountIn);
        uint256[] memory pairAmounts = RobinhoodDexLibrary.getAmountsOutFromPairInput(factory, pairAmountIn, path);
        require(pairAmounts[pairAmounts.length - 1] >= amountOutMin, 'RobinhoodDexRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        if (ethFee > 0) {
            TransferHelper.safeTransferETH(protocolFeeRecipient, ethFee);
            _emitProtocolFee(msg.sender, address(0), msg.value, ethFee, ACTION_SWAP);
        }
        IWETH(WETH).deposit{value: pairAmountIn}();
        require(IWETH(WETH).transfer(RobinhoodDexLibrary.pairFor(factory, path[0], path[1]), pairAmountIn), 'RobinhoodDexRouter: WETH_TRANSFER_FAILED');
        _swap(pairAmounts, path, to);
        amounts = pairAmounts;
        amounts[0] = msg.value;
    }

    function swapTokensForExactETH(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external override ensure(deadline) returns (uint256[] memory amounts) {
        _validatePathLength(path);
        require(path[path.length - 1] == WETH, 'RobinhoodDexRouter: INVALID_PATH');
        uint256[] memory pairAmounts = RobinhoodDexLibrary.getAmountsInForPairOutput(factory, amountOut, path);
        uint256 grossAmountIn = RobinhoodDexLibrary.grossUpAmount(pairAmounts[0]);
        require(grossAmountIn <= amountInMax, 'RobinhoodDexRouter: EXCESSIVE_INPUT_AMOUNT');
        _collectTokenWithKnownPairAmount(path[0], RobinhoodDexLibrary.pairFor(factory, path[0], path[1]), pairAmounts[0], ACTION_SWAP);
        _swap(pairAmounts, path, address(this));
        IWETH(WETH).withdraw(amountOut);
        TransferHelper.safeTransferETH(to, amountOut);
        amounts = pairAmounts;
        amounts[0] = grossAmountIn;
    }

    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external override ensure(deadline) returns (uint256[] memory amounts) {
        _validatePathLength(path);
        require(path[path.length - 1] == WETH, 'RobinhoodDexRouter: INVALID_PATH');
        uint256 pairAmountIn = RobinhoodDexLibrary.amountAfterProtocolFee(amountIn);
        uint256[] memory pairAmounts = RobinhoodDexLibrary.getAmountsOutFromPairInput(factory, pairAmountIn, path);
        require(pairAmounts[pairAmounts.length - 1] >= amountOutMin, 'RobinhoodDexRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        _collectTokenWithKnownGrossAmount(path[0], RobinhoodDexLibrary.pairFor(factory, path[0], path[1]), amountIn, ACTION_SWAP);
        _swap(pairAmounts, path, address(this));
        IWETH(WETH).withdraw(pairAmounts[pairAmounts.length - 1]);
        TransferHelper.safeTransferETH(to, pairAmounts[pairAmounts.length - 1]);
        amounts = pairAmounts;
        amounts[0] = amountIn;
    }

    function swapETHForExactTokens(
        uint256 amountOut,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable override ensure(deadline) returns (uint256[] memory amounts) {
        _validatePathLength(path);
        require(path[0] == WETH, 'RobinhoodDexRouter: INVALID_PATH');
        uint256[] memory pairAmounts = RobinhoodDexLibrary.getAmountsInForPairOutput(factory, amountOut, path);
        uint256 grossAmountIn = RobinhoodDexLibrary.grossUpAmount(pairAmounts[0]);
        require(grossAmountIn <= msg.value, 'RobinhoodDexRouter: EXCESSIVE_INPUT_AMOUNT');
        uint256 ethFee = grossAmountIn.sub(pairAmounts[0]);
        if (ethFee > 0) {
            TransferHelper.safeTransferETH(protocolFeeRecipient, ethFee);
            _emitProtocolFee(msg.sender, address(0), grossAmountIn, ethFee, ACTION_SWAP);
        }
        IWETH(WETH).deposit{value: pairAmounts[0]}();
        require(IWETH(WETH).transfer(RobinhoodDexLibrary.pairFor(factory, path[0], path[1]), pairAmounts[0]), 'RobinhoodDexRouter: WETH_TRANSFER_FAILED');
        _swap(pairAmounts, path, to);
        if (msg.value > grossAmountIn) {
            TransferHelper.safeTransferETH(msg.sender, msg.value.sub(grossAmountIn));
        }
        amounts = pairAmounts;
        amounts[0] = grossAmountIn;
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external override ensure(deadline) {
        _validatePathLength(path);
        _validateSupportingFeeOnTransferRecipient(path, to);
        _collectTokenWithKnownGrossAmount(path[0], RobinhoodDexLibrary.pairFor(factory, path[0], path[1]), amountIn, ACTION_SWAP);
        uint256 balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        require(
            IERC20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin,
            'RobinhoodDexRouter: INSUFFICIENT_OUTPUT_AMOUNT'
        );
    }

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable override ensure(deadline) {
        _validatePathLength(path);
        require(path[0] == WETH, 'RobinhoodDexRouter: INVALID_PATH');
        _validateSupportingFeeOnTransferRecipient(path, to);
        uint256 pairAmountIn = RobinhoodDexLibrary.amountAfterProtocolFee(msg.value);
        uint256 ethFee = msg.value.sub(pairAmountIn);
        if (ethFee > 0) {
            TransferHelper.safeTransferETH(protocolFeeRecipient, ethFee);
            _emitProtocolFee(msg.sender, address(0), msg.value, ethFee, ACTION_SWAP);
        }
        IWETH(WETH).deposit{value: pairAmountIn}();
        require(IWETH(WETH).transfer(RobinhoodDexLibrary.pairFor(factory, path[0], path[1]), pairAmountIn), 'RobinhoodDexRouter: WETH_TRANSFER_FAILED');
        uint256 balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        require(
            IERC20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin,
            'RobinhoodDexRouter: INSUFFICIENT_OUTPUT_AMOUNT'
        );
    }

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external override ensure(deadline) {
        _validatePathLength(path);
        require(path[path.length - 1] == WETH, 'RobinhoodDexRouter: INVALID_PATH');
        _collectTokenWithKnownGrossAmount(path[0], RobinhoodDexLibrary.pairFor(factory, path[0], path[1]), amountIn, ACTION_SWAP);
        uint256 wethBalanceBefore = IERC20(WETH).balanceOf(address(this));
        _swapSupportingFeeOnTransferTokens(path, address(this));
        uint256 amountOut = IERC20(WETH).balanceOf(address(this)).sub(wethBalanceBefore);
        require(amountOut >= amountOutMin, 'RobinhoodDexRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        IWETH(WETH).withdraw(amountOut);
        TransferHelper.safeTransferETH(to, amountOut);
    }

    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) external pure override returns (uint256 amountB) {
        return RobinhoodDexLibrary.quote(amountA, reserveA, reserveB);
    }

    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        external
        pure
        override
        returns (uint256 amountOut)
    {
        return RobinhoodDexLibrary.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut)
        external
        pure
        override
        returns (uint256 amountIn)
    {
        return RobinhoodDexLibrary.getAmountIn(amountOut, reserveIn, reserveOut);
    }

    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        override
        returns (uint256[] memory amounts)
    {
        return RobinhoodDexLibrary.getAmountsOut(factory, amountIn, path);
    }

    function getAmountsIn(uint256 amountOut, address[] calldata path)
        external
        view
        override
        returns (uint256[] memory amounts)
    {
        return RobinhoodDexLibrary.getAmountsIn(factory, amountOut, path);
    }
}
