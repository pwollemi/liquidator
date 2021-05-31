// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.8.0;

import "./UpgradeSource.sol";
import "./LiquidateWrapper.sol";

interface ERC677 {
    function transferAndCall(address, uint256, bytes calldata) external returns (bool);
    function balanceOf(address) external returns (uint256);
}

contract Liquidator is UpgradeSource {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    LiquidateWrapper public liquidate;
    address public HUSD;
    address public USDT;
    address public reserveToken;

    uint256 public slide;

    function initialize(
        address _governance,
        address payable _liquidateWrapper,
        address _HUSD,
        address _USDT
        ) public initializer {
        require(_liquidateWrapper != address(0) && _HUSD != address(0) && _USDT != address(0), "Liquidator: Invalid parameter");
        UpgradeSource.initialize(_governance);
        liquidate = LiquidateWrapper(_liquidateWrapper);
        HUSD = _HUSD;
        USDT = _USDT;
        reserveToken = _HUSD;
        slide = 1e8;
    }

    function liquidateERC20ForELA(address[] memory swapInPath, address token, address borrower, uint256 repayAmount, address collateral, address tokenBridge, string memory crossChainWithdraw) public returns (uint256) {
        require(tokenBridge != address(0) && bytes(crossChainWithdraw).length > 0, "Liquidator: Invalid parameter");
        require(token != address(0) && borrower != address(0) && repayAmount > 0 && collateral != address(0), "Liquidator: Invalid parameter");

        address underlying = CErc20Interface(token).underlying();

        uint256 amountIn;
        if (underlying != reserveToken) {
            uint256[] memory amountsIn = IUniswapV2Router02(liquidate.swapWrapper().router()).getAmountsIn(repayAmount, swapInPath);
            amountIn = amountsIn[0];
            if (IERC20(reserveToken).balanceOf(address(this)) < amountIn) {
                amountIn = IERC20(reserveToken).balanceOf(address(this));
                uint256[] memory amountsOut = IUniswapV2Router02(liquidate.swapWrapper().router()).getAmountsOut(amountIn, swapInPath);
                repayAmount = amountsOut[amountsOut.length - 1];
            }
        } else {
            repayAmount = IERC20(reserveToken).balanceOf(address(this)) > repayAmount ? repayAmount : IERC20(reserveToken).balanceOf(address(this));
            amountIn = repayAmount;
        }
        IERC20(reserveToken).safeApprove(address(liquidate), amountIn);

        uint256 elaAmount = liquidate.liquidateERC20(swapInPath, token, borrower, repayAmount, collateral, amountIn);
        // send ELA from heco to ela eth side chain
        ERC677(CErc20Interface(collateral).underlying()).transferAndCall(tokenBridge, elaAmount, bytes(crossChainWithdraw));
        return elaAmount;
    }

    function liquidateETHForELA(address[] memory swapInPath, address borrower, uint256 repayAmount, address collateral, address tokenBridge, string memory crossChainWithdraw) public returns (uint256) {
        require(tokenBridge != address(0) && bytes(crossChainWithdraw).length > 0, "Liquidator: Invalid parameter");
        require(borrower != address(0) && repayAmount > 0 && collateral != address(0), "Liquidator: Invalid parameter");

        uint256[] memory amountsIn = IUniswapV2Router02(liquidate.swapWrapper().router()).getAmountsIn(repayAmount, swapInPath);
        uint256 amountIn = amountsIn[0];
        if (IERC20(reserveToken).balanceOf(address(this)) < amountsIn[0]) {
            amountIn = IERC20(reserveToken).balanceOf(address(this));
            uint256[] memory amountsOut = IUniswapV2Router02(liquidate.swapWrapper().router()).getAmountsOut(amountIn, swapInPath);
            repayAmount = amountsOut[amountsOut.length - 1];
        }

        IERC20(reserveToken).safeApprove(address(liquidate), amountIn);

        uint256 elaAmount = liquidate.liquidateETH(swapInPath, borrower, repayAmount, collateral, amountIn);
        // send ELA from heco to ela eth side chain
        ERC677(CErc20Interface(collateral).underlying()).transferAndCall(tokenBridge, elaAmount, bytes(crossChainWithdraw));
        return elaAmount;
    }

    function liquidateERC20(address[] memory swapInPath, address token, address borrower, uint256 repayAmount, address collateral, address[] memory swapOutPath) public returns (uint256) {
        require(token != address(0) && borrower != address(0) && collateral != address(0), "Liquidator: Invalid parameter");

        address underlying = CErc20Interface(token).underlying();

        uint256 amountIn;
        if (underlying != reserveToken) {
            uint256[] memory amountsIn = IUniswapV2Router02(liquidate.swapWrapper().router()).getAmountsIn(repayAmount, swapInPath);
            amountIn = amountsIn[0];
            if (IERC20(reserveToken).balanceOf(address(this)) < amountIn) {
                amountIn = IERC20(reserveToken).balanceOf(address(this));
                uint256[] memory amountsOut = IUniswapV2Router02(liquidate.swapWrapper().router()).getAmountsOut(amountIn, swapInPath);
                repayAmount = amountsOut[amountsOut.length - 1];
            }
        } else {
            repayAmount = IERC20(reserveToken).balanceOf(address(this)) > repayAmount ? repayAmount : IERC20(reserveToken).balanceOf(address(this));
            amountIn = repayAmount;
        }

        IERC20(reserveToken).safeApprove(address(liquidate), amountIn);
        if (CErc20Interface(collateral).underlying() == reserveToken) {
            uint256 amountOut = liquidate.liquidateERC20(swapInPath, token, borrower, repayAmount, collateral, amountIn);
            require(amountOut > amountIn.add(slide));
            return amountOut;
        } else {
            return liquidate.liquidateERC20AndSell(swapInPath, token, borrower, repayAmount, collateral, amountIn, swapOutPath, slide);
        }
    }

    function liquidateETH(address[] memory swapInPath, address borrower, uint256 repayAmount, address collateral, address[] memory swapOutPath) public returns (uint256) {
        require(borrower != address(0) && collateral != address(0) && swapInPath.length > 1, "Liquidator: Invalid parameter");

        uint256[] memory amountsIn = IUniswapV2Router02(liquidate.swapWrapper().router()).getAmountsIn(repayAmount, swapInPath);
        uint256 amountIn = amountsIn[0];
        if (IERC20(reserveToken).balanceOf(address(this)) < amountsIn[0]) {
            amountIn = IERC20(reserveToken).balanceOf(address(this));
            uint256[] memory amountsOut = IUniswapV2Router02(liquidate.swapWrapper().router()).getAmountsOut(amountIn, swapInPath);
            repayAmount = amountsOut[amountsOut.length - 1];
        }

        IERC20(reserveToken).safeApprove(address(liquidate), amountIn);

        if (CErc20Interface(collateral).underlying() == reserveToken) {
            uint256 amountOut = liquidate.liquidateETH(swapInPath, borrower, repayAmount, collateral, amountIn);
            require(amountOut > amountIn.add(slide));
            return amountOut;
        } else {
            return liquidate.liquidateETHAndSell(swapInPath, borrower, repayAmount, collateral, amountIn, swapOutPath, slide);
        }
    }

    function setUAddress(address _HUSD, address _USDT) public onlyGovernance {
        require(_USDT != address(0) && _USDT != address(0), "Liquidator: Invalid parameter");
        HUSD = _HUSD;
        USDT = _USDT;
    }

    function setReserveToken(address _reserve) public onlyGovernance {
        require(_reserve != address(0), "Liquidator: Invalid parameter");
        reserveToken = _reserve;
    }

    function setSlide(uint256 _slide) public onlyGovernance { 
        slide = _slide;
    }

    function withdrawERC20(address _token, address _account, uint256 amount) public onlyGovernance returns (uint256) {
        require(_token != address(0) && _account != address(0) && amount > 0, "Liquidator: Invalid parameter");
        IERC20 token = IERC20(_token);
        if (amount > token.balanceOf(address(this))) {
            amount = token.balanceOf(address(this));
        }
        token.safeTransfer(_account, amount);
        return amount;
    }

    function withdraw(address payable _account, uint256 amount) public onlyGovernance returns (uint256) {
        require(_account != address(0) && amount > 0, "Liquidator: Invalid parameter");
        if (amount > address(this).balance) {
            amount = address(this).balance;
        }
        _account.transfer(amount);
        return amount;
    }
}
