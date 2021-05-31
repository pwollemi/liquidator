// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.8.0;

import "./UpgradeSource.sol";
import "./SwapWrapper.sol";
import "./uniswap/IUniswapV2Router02.sol";
import "./compound/CTokenInterfaces.sol";
import "./compound/CEther.sol";

contract LiquidateWrapper is UpgradeSource {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    SwapWrapper public swapWrapper;

    address public CEtherAddress;
    address public reserveToken;

    event compoundError(uint256 errorCode);
    event Gained(address token, uint256 amount);

    function initialize(
        address _governance,
        address payable _swapWrapper,
        address _CEtherAddress
        ) public initializer {
        require(_swapWrapper != address(0) && _CEtherAddress != address(0) , "Liquidator: Invalid parameter");
        UpgradeSource.initialize(_governance);
        swapWrapper = SwapWrapper(_swapWrapper);
        CEtherAddress = _CEtherAddress;
    }

    function liquidateERC20AndSell(address[] memory swapInPath, address token, address borrower, uint256 repayAmount,
            address collateral, uint256 amountInMax, address[] memory swapOutPath, uint256 slide) public returns (uint256) {
        require(token != address(0) && borrower != address(0) && collateral != address(0), "Liquidator: Invalid parameter");

        (uint256 amountIn,) = liquidateERC20Internal(swapInPath, token, borrower, repayAmount, collateral, amountInMax, true);
        return sellToken(amountIn, collateral, swapOutPath, slide);
    }

    function sellToken(uint256 amountIn, address collateral, address[] memory swapOutPath, uint256 slide) internal returns (uint256) {
        uint256 amountOut;
        if (collateral == CEtherAddress) {
            (,amountOut) = swapWrapper.swapExactETHForTokens.value(address(this).balance)(swapOutPath, 0);
        } else {
            uint256 balance = IERC20(CErc20Interface(collateral).underlying()).balanceOf(address(this));
            IERC20(CErc20Interface(collateral).underlying()).approve(address(swapWrapper), balance);
            (,amountOut) = swapWrapper.swapExactTokensForTokens(balance, swapOutPath, 0);
        }

        IERC20(swapOutPath[swapOutPath.length - 1]).safeTransfer(msg.sender, amountOut);
        require(amountOut > amountIn.add(slide));
        emit Gained(swapOutPath[swapOutPath.length - 1], amountOut.sub(amountIn));

        return amountOut;
    }

    function liquidateERC20(address[] memory swapInPath, address token,
            address borrower, uint256 repayAmount, address collateral, uint256 amountInMax) public returns (uint256) {
        require(token != address(0) && borrower != address(0) && collateral != address(0), "Liquidator: Invalid parameter");

        (, uint256 amountOut) = liquidateERC20Internal(swapInPath, token, borrower, repayAmount, collateral, amountInMax, false);
        return amountOut;
    }

    function liquidateERC20Internal(address[] memory swapInPath, address token,
            address borrower, uint256 repayAmount, address collateral, uint256 amountInMax, bool sell) internal returns (uint256 amountIn, uint256 amountOut) {
        address underlying = CErc20Interface(token).underlying();
        if (swapInPath.length == 0) {
            amountIn = repayAmount;
            IERC20(underlying).safeTransferFrom(msg.sender, address(this), repayAmount);
        } else {
            uint256[] memory amountsIn = IUniswapV2Router02(swapWrapper.router()).getAmountsIn(repayAmount, swapInPath);
            amountIn = amountsIn[0];
            IERC20(swapInPath[0]).safeTransferFrom(msg.sender, address(this), amountIn);
            IERC20(swapInPath[0]).safeApprove(address(swapWrapper), amountIn);
            (,repayAmount) = swapWrapper.swapTokensForExactTokens(repayAmount, swapInPath, amountInMax);
        }

        IERC20(underlying).safeApprove(token, repayAmount);
        CErc20Interface(token).liquidateBorrow(borrower, repayAmount, CTokenInterface(collateral));

        CErc20Interface(collateral).redeem(CTokenInterface(collateral).balanceOf(address(this)));

        if (collateral == CEtherAddress) {
            amountOut = address(this).balance;
            if (!sell) {
                msg.sender.transfer(amountOut);
            }
        } else {
            amountOut = IERC20(CErc20Interface(collateral).underlying()).balanceOf(address(this));
            if (!sell) {
                IERC20(CErc20Interface(collateral).underlying()).safeTransfer(msg.sender, amountOut);
            }
        }
    }

    function liquidateETHAndSell(address[] memory swapInPath, address borrower,
        uint256 repayAmount, address collateral, uint256 amountInMax, address[] memory swapOutPath, uint256 slide) public returns (uint256) {
        require(borrower != address(0) && collateral != address(0), "Liquidator: Invalid parameter");

        (uint256 amountIn,) =  liquidateETHInternal(swapInPath, borrower, repayAmount, collateral, amountInMax, true);
        return sellToken(amountIn, collateral, swapOutPath, slide);
    }

    function liquidateETH(address[] memory swapInPath, address borrower, uint256 repayAmount, address collateral, uint256 amountInMax) payable public returns (uint256) {
        require(borrower != address(0) && collateral != address(0), "Liquidator: Invalid parameter");
        (, uint256 amountOut) =  liquidateETHInternal(swapInPath, borrower, repayAmount, collateral, amountInMax, false);
        return amountOut;
    }

    function liquidateETHInternal(address[] memory swapInPath, address borrower,
            uint256 repayAmount, address collateral, uint256 amountInMax, bool sell) payable public returns (uint256 amountIn, uint256 amountOut) {
        if (swapInPath.length == 0) {
            require(msg.value == repayAmount, "Liquidator: input value is not equal to repayAmount");
            amountIn = msg.value;
        } else {
            uint256[] memory amountsIn = IUniswapV2Router02(swapWrapper.router()).getAmountsIn(repayAmount, swapInPath);
            amountIn = amountsIn[0];
            IERC20(swapInPath[0]).safeTransferFrom(msg.sender, address(this), amountIn);
            IERC20(swapInPath[0]).safeApprove(address(swapWrapper), amountIn);
            (,repayAmount) = swapWrapper.swapTokensForExactETH(repayAmount, swapInPath, amountInMax);
        }

        CEther(CEtherAddress).liquidateBorrow.value(repayAmount)(borrower, collateral);

        CErc20Interface(collateral).redeem(CTokenInterface(collateral).balanceOf(address(this)));
        
        if (collateral == CEtherAddress) {
            amountOut = address(this).balance;
            if (!sell) {
                msg.sender.transfer(amountOut);
            }
        } else {
            amountOut = IERC20(CErc20Interface(collateral).underlying()).balanceOf(address(this));
            if (!sell) {
                IERC20(CErc20Interface(collateral).underlying()).safeTransfer(msg.sender, amountOut);
            }
        }
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

    function() external payable {}

    function setSwapWrapper(address payable _swapWrapper) public onlyGovernance {
        require(_swapWrapper != address(0), "Liquidator: Invalid parameter");
        swapWrapper = SwapWrapper(_swapWrapper);
    }

    function setCEtherAddress(address _CEtherAddress) public onlyGovernance {
        require(_CEtherAddress != address(0), "Liquidator: Invalid parameter");
        CEtherAddress = _CEtherAddress;
    }
}
