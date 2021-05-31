// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.8.0;

import "./SwapWrapper.sol";
import "./dependency.sol";
import "./compound/CTokenInterfaces.sol";
import "./compound/CEther.sol";
import "./uniswap/IUniswapV2Router02.sol";

contract SwapRepayTool is Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    SwapWrapper public swapWrapper;

    event Repayed(address borrower, address token, uint256 amount);

    constructor(address payable _swapWrapper) public {
        swapWrapper = SwapWrapper(_swapWrapper);
    }

    function swapExactERC20RepayERC20(uint256 amountIn, address[] calldata path, address repayCToken, uint256 amountOutMin) external {
        require(amountIn > 0 && path.length > 1 && repayCToken != address(0), "SwapRepayTool: Invalid parameter");
        require(CErc20Interface(repayCToken).underlying() == path[path.length - 1], "ctoken underlying is not swap out token");

        IERC20(path[0]).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(path[0]).safeApprove(address(swapWrapper), amountIn);

        (, uint256 ret2) = swapWrapper.swapExactTokensForTokens(amountIn, path, amountOutMin);

        IERC20(path[path.length - 1]).safeApprove(repayCToken, ret2);
        CErc20Interface(repayCToken).repayBorrowBehalf(msg.sender, ret2);
        emit Repayed(msg.sender, repayCToken, ret2);
    }

    function swapERC20RepayExactERC20(address[] memory path, address repayCToken, uint256 repayAmount, uint256 amountInMax) public {
        require(repayAmount > 0 && path.length > 1 && repayCToken != address(0), "SwapRepayTool: Invalid parameter");
        require(CErc20Interface(repayCToken).underlying() == path[path.length - 1], "ctoken underlying is not swap out token");

        uint256[] memory amountsIn = IUniswapV2Router02(swapWrapper.router()).getAmountsIn(repayAmount, path);
        require(amountsIn[0] <= amountInMax, "SwapRepayTool: amountIn is greater than amountInMax");
        IERC20(path[0]).safeTransferFrom(msg.sender, address(this), amountsIn[0]);
        IERC20(path[0]).safeApprove(address(swapWrapper), amountsIn[0]);

        (, uint256 ret2) = swapWrapper.swapTokensForExactTokens(repayAmount, path, amountInMax);

        IERC20(path[path.length - 1]).safeApprove(repayCToken, ret2);
        CErc20Interface(repayCToken).repayBorrowBehalf(msg.sender, ret2);
        emit Repayed(msg.sender, repayCToken, ret2);
    }

    function swapExactERC20RepayETH(uint256 amountIn, address[] memory path, address CEtherAddress, uint256 amountOutMin) public {
        require(amountIn > 0 && path.length > 1 && CEtherAddress != address(0), "SwapRepayTool: Invalid parameter");

        IERC20(path[0]).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(path[0]).safeApprove(address(swapWrapper), amountIn);

        (, uint256 ret2) = swapWrapper.swapExactTokensForETH(amountIn, path, amountOutMin);

        CEther(CEtherAddress).repayBorrowBehalf.value(ret2)(msg.sender);
        emit Repayed(msg.sender, CEtherAddress, ret2);
    }

    function swapERC20RepayExactETH(address[] memory path, address CEtherAddress, uint256 repayAmount, uint256 amountInMax) public {
        require(repayAmount > 0 && path.length > 1 && CEtherAddress != address(0), "SwapRepayTool: Invalid parameter");

        uint256[] memory amountsIn = IUniswapV2Router02(swapWrapper.router()).getAmountsIn(repayAmount, path);
        require(amountsIn[0] <= amountInMax, "SwapRepayTool: amountIn is greater than amountInMax");
        IERC20(path[0]).safeTransferFrom(msg.sender, address(this), amountsIn[0]);
        IERC20(path[0]).safeApprove(address(swapWrapper), amountsIn[0]);

        (, uint256 ret2) = swapWrapper.swapTokensForExactETH(repayAmount, path, amountInMax);

        CEther(CEtherAddress).repayBorrowBehalf.value(ret2)(msg.sender);
        emit Repayed(msg.sender, CEtherAddress, ret2);
    }

    function swapERC20RepayERC20All(address[] calldata path, address repayCToken, uint256 amountInMax) external {
        require(path.length > 1 && repayCToken != address(0), "SwapRepayTool: Invalid parameter");
        require(CErc20Interface(repayCToken).underlying() == path[path.length - 1], "ctoken underlying is not swap out token");

        uint256 borrowAmount = CTokenInterface(repayCToken).borrowBalanceCurrent(msg.sender);
        swapERC20RepayExactERC20(path, repayCToken, borrowAmount, amountInMax);
    }

    function swapERC20RepayETHAll(address[] calldata path, address CEtherAddress, uint256 amountInMax) external {
        require(path.length > 1 && CEtherAddress != address(0), "SwapRepayTool: Invalid parameter");
        uint256 borrowAmount = CEther(CEtherAddress).borrowBalanceCurrent(msg.sender);
        swapERC20RepayExactETH(path, CEtherAddress, borrowAmount, amountInMax);
    }

    function swapETHRepayERC20All(address[] calldata path, address repayCToken) external payable {
        require(path.length > 1 && repayCToken != address(0), "SwapRepayTool: Invalid parameter");

        uint256 borrowAmount = CTokenInterface(repayCToken).borrowBalanceCurrent(msg.sender);
        uint256[] memory amountsIn = IUniswapV2Router02(swapWrapper.router()).getAmountsIn(borrowAmount, path);
        require(msg.value >= amountsIn[0], "SwapRepayTool: ETH is not enough");

        (, uint256 ret2) = swapWrapper.swapETHForExactTokens.value(amountsIn[0])(borrowAmount, path, msg.value);

        IERC20(path[path.length - 1]).safeApprove(repayCToken, ret2);
        CErc20Interface(repayCToken).repayBorrowBehalf(msg.sender, ret2);
        emit Repayed(msg.sender, repayCToken, ret2);

        // send ETH back
        if (amountsIn[0] < msg.value) {
            msg.sender.transfer(msg.value.sub(amountsIn[0]));
        }
    }

    function swapExactETHRepayERC20(address[] calldata path, address repayCToken, uint256 amountOutMin) external payable {
        require(path.length > 1 && repayCToken != address(0), "SwapRepayTool: Invalid parameter");

        (, uint256 ret2) = swapWrapper.swapExactETHForTokens.value(msg.value)(path, amountOutMin);

        IERC20(path[path.length - 1]).safeApprove(repayCToken, ret2);
        CErc20Interface(repayCToken).repayBorrowBehalf(msg.sender, ret2);
        emit Repayed(msg.sender, repayCToken, ret2);
    }

    function() external payable {}

    function withdrawERC20(address _token, address _account, uint256 amount) public onlyOwner returns (uint256) {
        require(_token != address(0) && _account != address(0) && amount > 0, "Liquidator: Invalid parameter");
        IERC20 token = IERC20(_token);
        if (amount > token.balanceOf(address(this))) {
            amount = token.balanceOf(address(this));
        }
        token.safeTransfer(_account, amount);
        return amount;
    }

    function withdraw(address payable _account, uint256 amount) public onlyOwner returns (uint256) {
        require(_account != address(0) && amount > 0, "Liquidator: Invalid parameter");
        if (amount > address(this).balance) {
            amount = address(this).balance;
        }
        _account.transfer(amount);
        return amount;
    }
}

