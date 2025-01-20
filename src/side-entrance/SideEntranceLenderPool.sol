// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

interface IFlashLoanEtherReceiver {
    function execute() external payable;
}

contract SideEntranceLenderPool {
    mapping(address => uint256) public balances;

    error RepayFailed();

    event Deposit(address indexed who, uint256 amount);
    event Withdraw(address indexed who, uint256 amount);

    function deposit() external payable {
        unchecked {
            balances[msg.sender] += msg.value;
        }
        emit Deposit(msg.sender, msg.value);
    }

    function withdraw() external {
        uint256 amount = balances[msg.sender];  

        delete balances[msg.sender];    //update state before interact
        emit Withdraw(msg.sender, amount);

        SafeTransferLib.safeTransferETH(msg.sender, amount);    //interact
    }

    function flashLoan(uint256 amount) external {
        uint256 balanceBefore = address(this).balance;  

        IFlashLoanEtherReceiver(msg.sender).execute{value: amount}();

        if (address(this).balance < balanceBefore) {
            revert RepayFailed();
        }
    }
}

/*

The key exploit here is the flashLoan() function allows the arbritary msg.sender to do their own execute(), and there is also an accounting problem
during deposit() and withdraw(), someone can use the borrowed(flashloaned funds) and then in their execute, call deposit, and deposit the borrowed amount.
balance[msg.sender] += amount, and then, it will pass the address(this.balance < balanceBefore)

address(this).balance doesnt know and just thinks all 100eth is his, but didnt know its compromised under balances[msg.sender]?


bad actor calls flashloan(): pool 0ETH, badactor 100ETH
bad actor execute() within flashloan, deposit(): pool 100ETH, balances[msg.sender]:100ETH, msg.sender: 0ETH
bad actor calls withdraw(): pool 0ETH, badactor 100ETH

*/