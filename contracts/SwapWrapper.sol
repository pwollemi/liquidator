// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.8.0;

import "./UpgradeSource.sol";
import "./uniswap/IUniswapV2Router02.sol";
import "./SwapMining.sol";

contract SwapWrapper is UpgradeSource {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    IUniswapV2Router02 public router;
    address public factory;

    SwapMining public mdexSwapMining;
    address public mdexToken;

    event TokenSwitched(address tokenIn, uint256 amountIn, address tokenOut, uint256 amountOut);

    function initialize(address _governance, address _factory, address _router) public initializer {
        require(_factory != address(0) && _router != address(0), "SwapWrapper: Invalid parameter");
        UpgradeSource.initialize(_governance);
        factory = _factory;
        router = IUniswapV2Router02(_router);
    }

    function swapTokensForExactTokens(uint256 amountOut, address[] calldata path, uint256 amountInMax) external returns (uint256, uint256) {
        require(amountOut > 0 && path.length > 1, "SwapWrapper: Invalid parameter");

        uint256[] memory amountsIn = router.getAmountsIn(amountOut, path);
        require(amountsIn[0] <= amountInMax, "SwapWrapper: exceed amountInMax");
        IERC20(path[0]).safeTransferFrom(msg.sender, address(this), amountsIn[0]);
        IERC20(path[0]).safeApprove(address(router), amountsIn[0]);

        uint256 deadline = block.timestamp + 10;

        uint256[] memory amounts = router.swapTokensForExactTokens(
            amountOut,
            amountInMax,
            path,
            msg.sender,
            deadline);
        emit TokenSwitched(path[0], amounts[0], path[path.length - 1], amounts[amounts.length - 1]);

        return (amounts[0], amounts[amounts.length - 1]);
    }

    function swapExactTokensForTokens(uint256 amountIn, address[] calldata path, uint256 amountOutMin) external returns (uint256, uint256) {
        require(amountIn > 0 && path.length > 1, "SwapWrapper: Invalid parameter");

        IERC20(path[0]).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(path[0]).safeApprove(address(router), amountIn);

        uint256 deadline = block.timestamp + 10;

        uint256[] memory amounts = router.swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            msg.sender,
            deadline);
        emit TokenSwitched(path[0], amounts[0], path[path.length - 1], amounts[amounts.length - 1]);

        return (amounts[0], amounts[amounts.length - 1]);
    }

    function swapTokensForExactETH(uint256 amountOut, address[] calldata path, uint256 amountInMax) external returns (uint256, uint256) {
        require(amountOut > 0 && path.length > 1, "SwapWrapper: Invalid parameter");

        uint256[] memory amountsIn = router.getAmountsIn(amountOut, path);
        require(amountsIn[0] <= amountInMax, "SwapWrapper: exceed amountInMax");
        IERC20(path[0]).safeTransferFrom(msg.sender, address(this), amountsIn[0]);
        IERC20(path[0]).safeApprove(address(router), amountsIn[0]);

        uint256 deadline = block.timestamp + 10;

        uint256[] memory amounts = router.swapTokensForExactETH(
            amountOut,
            amountsIn[0],
            path,
            msg.sender,
            deadline);
        emit TokenSwitched(path[0], amounts[0], path[path.length - 1], amounts[amounts.length - 1]);

        return (amounts[0], amounts[amounts.length - 1]);
    }

    function swapExactTokensForETH(uint256 amountIn, address[] calldata path, uint256 amountOutMin) external returns (uint256, uint256) {
        require(amountIn > 0 && path.length > 1, "SwapWrapper: Invalid parameter");

        IERC20(path[0]).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(path[0]).safeApprove(address(router), amountIn);

        uint256 deadline = block.timestamp + 10;

        uint256[] memory amounts = router.swapExactTokensForETH(
            amountIn,
            amountOutMin,
            path,
            msg.sender,
            deadline);
        emit TokenSwitched(path[0], amounts[0], path[path.length - 1], amounts[amounts.length - 1]);

        return (amounts[0], amounts[amounts.length - 1]);
    }

    function swapExactETHForTokens(address[] calldata path, uint256 amountOutMin) external payable returns (uint256, uint256) {
        require(path.length > 1, "SwapWrapper: Invalid parameter");
        require(msg.value > 0, "SwapWrapper: value is 0");

        uint256 deadline = block.timestamp + 10;

        uint256[] memory amounts = router.swapExactETHForTokens.value(msg.value)(
            amountOutMin,
            path,
            msg.sender,
            deadline);
        emit TokenSwitched(path[0], amounts[0], path[path.length - 1], amounts[amounts.length - 1]);

        return (amounts[0], amounts[amounts.length - 1]);
    }

    function swapETHForExactTokens(uint256 amountOut, address[] calldata path, uint256 amountInMax) external payable returns (uint256, uint256) {
        require(amountOut > 0 && path.length > 1, "SwapWrapper: Invalid parameter");
        uint[] memory amountsIn = router.getAmountsIn(amountOut, path);
        require(amountsIn[0] <= amountInMax, "SwapWrapper: exceed amountInMax");
        require(msg.value >= amountsIn[0], "SwapWrapper: value is not enough");

        uint256 deadline = block.timestamp + 10;

        uint256[] memory amounts = router.swapETHForExactTokens.value(amountsIn[0])(
            amountOut,
            path,
            msg.sender,
            deadline);
        emit TokenSwitched(path[0], amounts[0], path[path.length - 1], amounts[amounts.length - 1]);
    
        // send ETH back
        if (amounts[0] < msg.value) {
            msg.sender.transfer(msg.value.sub(amounts[0]));
        }

        return (amounts[0], amounts[amounts.length - 1]);
    }

    function() external payable {}

    function setSwapAddress(address _factory, address _router) external onlyGovernance {
        require(_factory != address(0) && _router != address(0));
        factory = _factory;
        router = IUniswapV2Router02(_router);
    }

    function setMdexSwapMining(address _swapMining, address _mdexToken) external onlyGovernance {
        require(_swapMining != address(0) && _mdexToken != address(0), "address can not be zero");
        mdexSwapMining = SwapMining(_swapMining);
        mdexToken = _mdexToken;
    }

    function getMdexReward(address _recipient) external onlyGovernance returns (uint256) {
        require(_recipient != address(0), "address can not be zero");

        mdexSwapMining.takerWithdraw();
        IERC20 token = IERC20(mdexToken);
        uint256 amount = token.balanceOf(address(this));
        token.safeTransfer(_recipient, amount);
        return amount;
    }
}
