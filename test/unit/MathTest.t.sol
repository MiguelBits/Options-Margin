pragma solidity ^0.8.18;

//HELPERS
import "forge-std/Test.sol";
import {ConvertDecimals, Math} from "../../src/libraries/ConvertDecimals.sol";

contract MathTest is Test {
    function test_floor() public {
        uint256 n = 7936795623706789182;
        uint256 c = Math.ceil(n, 10 ** 12);
        uint256 e = 7936795000000000000; //expected
        uint256 v = (Math.floor(n, 10 ** 12));
        console.log("n: %s", n);
        console.log("e: %s", e);
        console.log("v: %s", v);
        console.log("c: %s", c);
        assertTrue(v == e, "floor failed");
    }

    function test_ConvertRoundDown() public {
        uint256 n = 7936795623706789182;
        uint256 c = Math.ceil(n, 10 ** 12);
        uint256 e = 7936795; //expected
        uint256 v = (Math.floor(n, 10 ** 12));
        console.log("n: %s", n);
        console.log("e: %s", e);
        console.log("v: %s", v);
        console.log("c: %s", c);
        uint256 a = ConvertDecimals.convertFrom18AndRoundDown(n, 6);
        console.log("a: %s", a);
        assertTrue(a == e, "round down failed");
    }
}
