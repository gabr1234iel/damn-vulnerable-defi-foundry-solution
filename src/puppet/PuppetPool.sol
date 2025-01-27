// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {DamnValuableToken} from "../DamnValuableToken.sol";

contract PuppetPool is ReentrancyGuard {
    // This is a simple pool that allows users to borrow tokens by depositing collateral in ETH, currently pool has 100000 DVT in liquidity
    using Address for address payable;  // Address extension to handle payable addresses

    uint256 public constant DEPOSIT_FACTOR = 2; // Collateral factor (must depost 2x of the borrowed amount in ETH)

    address public immutable uniswapPair; // Uniswap pair address
    DamnValuableToken public immutable token; // Token address

    mapping(address => uint256) public deposits; //maps user address to their deposit

    error NotEnoughCollateral();
    error TransferFailed();

    event Borrowed(address indexed account, address recipient, uint256 depositRequired, uint256 borrowAmount);

    constructor(address tokenAddress, address uniswapPairAddress) {
        token = DamnValuableToken(tokenAddress); // Token address
        uniswapPair = uniswapPairAddress; // Uniswap pair address
    }

    // Allows borrowing tokens by first depositing two times their value in ETH
    function borrow(uint256 amount, address recipient) external payable nonReentrant {
        uint256 depositRequired = calculateDepositRequired(amount);     //this might get an inaccurate value due to the use of the Uniswap pair balance

        if (msg.value < depositRequired) {
            revert NotEnoughCollateral();
        }

        if (msg.value > depositRequired) {
            unchecked {
                payable(msg.sender).sendValue(msg.value - depositRequired);
            }
        }

        unchecked {
            deposits[msg.sender] += depositRequired;
        }

        // Fails if the pool doesn't have enough tokens in liquidity
        if (!token.transfer(recipient, amount)) {
            revert TransferFailed();
        }

        emit Borrowed(msg.sender, recipient, depositRequired, amount);
    }

    function calculateDepositRequired(uint256 amount) public view returns (uint256) {
        return amount * _computeOraclePrice() * DEPOSIT_FACTOR / 10 ** 18; // calculates the deposit required in wei
    }

    function _computeOraclePrice() private view returns (uint256) {
        // calculates the price of the token in wei according to Uniswap pair
        return uniswapPair.balance * (10 ** 18) / token.balanceOf(uniswapPair);     // Uniswap pair balance (in wei) * 10^18 / token balance in Uniswap pair
    }
    // exploitable because the price of the token is calculated using the Uniswap pair balance, which can be manipulated by the attacker by dumping the tokens causing price to drop
    // x*y=k
}
