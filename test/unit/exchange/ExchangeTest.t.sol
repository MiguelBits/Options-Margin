pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {Helper} from "../../helpers/Helper.sol";

import {ERC20} from "@solmate/tokens/ERC20.sol";
import {IVXExchange} from "../../../src/exchange/IVXExchange.sol";
import {IVXOracle} from "../../../src/periphery/IVXOracle.sol";
import {IERC20} from "../../../src/interface/IERC20.sol";
import {IVXLP} from "../../../src/liquidity/IVXLP.sol";

contract ExchangeTest is Helper {
    address weth;
    address usdc;

    address GmxExchangeRouter;
    address GmxOrderVault;
    address GmxRouter;
    address LvLContract;

    IVXOracle _oracle;
    IVXLP _lp;

    function setUpUniswap() public {
        vm.createSelectFork(vm.envString("ARB_URL"));

        weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; //arbitrum weth
        usdc = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8; //arbitrum usdc

        deployExchange();
    }

    function test_swapOnUniswap() public {
        setUpUniswap();
        address _user = 0x0dF5dfd95966753f01cb80E76dc20EA958238C46; //weth whale

        console.log("exchange address", address(exchange));

        address tokenIn = weth;
        address tokenOut = usdc;
        uint256 amountIn = 2 ether;

        uint256 tokenIn_whale_balance_before = IERC20(tokenIn).balanceOf(_user);
        console.log("tokenIn_whale_balance_before ", tokenIn_whale_balance_before);
        uint256 tokenOut_whale_balance_before = IERC20(tokenOut).balanceOf(_user);
        console.log("tokenOut_whale_balance_before", tokenOut_whale_balance_before);

        vm.startPrank(_user);
        IERC20(tokenIn).approve(address(exchange), amountIn);
        uint256 amountOut = exchange.swapOnUniswap(tokenIn, tokenOut, amountIn, 0, _user);
        vm.stopPrank();

        console.log("amountOut", amountOut);

        uint256 tokenIn_whale_balance_after = IERC20(tokenIn).balanceOf(_user);
        console.log("tokenIn_whale_balance_after  ", tokenIn_whale_balance_after);
        assertTrue(tokenIn_whale_balance_before > tokenIn_whale_balance_after, "tokenIn should be less after swap");

        uint256 tokenOut_whale_balance_after = IERC20(tokenOut).balanceOf(_user);
        console.log("tokenOut_whale_balance_after ", tokenOut_whale_balance_after);
        assertTrue(tokenOut_whale_balance_before < tokenOut_whale_balance_after, "tokenOut should be more after swap");

        uint256 exchangeBalance = IERC20(tokenOut).balanceOf(address(exchange));
        console.log("exchangeBalance", exchangeBalance);
        assertTrue(exchangeBalance == 0, "exchange should have no balance after swap");
    }
}
