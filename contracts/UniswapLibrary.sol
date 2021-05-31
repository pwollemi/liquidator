// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.8.0;

import "./uniswap/IUniswapV2Pair.sol";
import "./dependency.sol";

library UniswapLibrary {
    using SafeMath for uint256;

    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, 'UniswapV2Library: IDENTICAL_ADDRESSES');
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'UniswapV2Library: ZERO_ADDRESS');
    }

    function pairFor(address factory, address tokenA, address tokenB) internal pure returns (address pair) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        pair = address(uint(keccak256(abi.encodePacked(
                hex'ff',
                factory,
                keccak256(abi.encodePacked(token0, token1)),
                //hex'77d35d84db83d346d845a23b35a87b92e27c84e765e40c1ea3baaf83c1c6ad3d' // heco testnet init code hash
                hex'2ad889f82040abccb2649ea6a874796c1601fb67f91a747a80e08860c73ddf24' // heco mdex init code hash
            ))));
    }

    function getReserves(address factory, address tokenA, address tokenB) public view returns (uint256 reserveA, uint256 reserveB) {
        (address token0, ) = sortTokens(tokenA, tokenB);
        IUniswapV2Pair pair = IUniswapV2Pair(pairFor(factory, tokenA, tokenB));
        (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }
}
