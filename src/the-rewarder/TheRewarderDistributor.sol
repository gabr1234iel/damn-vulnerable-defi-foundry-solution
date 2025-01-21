// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";

// Distribution data for each token
struct Distribution {
    uint256 remaining;  // remaining amount to be distributed
    uint256 nextBatchNumber;    // next batch number to be distributed
    mapping(uint256 batchNumber => bytes32 root) roots; // merkle roots for each batch
    mapping(address claimer => mapping(uint256 word => uint256 bits)) claims;   // claimed bits for each claimer
}


// Claim data for each claim
struct Claim {
    uint256 batchNumber;    // batch number
    uint256 amount;     // amount to be claimed
    uint256 tokenIndex;     // token index
    bytes32[] proof;        // merkle proof
}

/**
 * An efficient token distributor contract based on Merkle proofs and bitmaps
 */
contract TheRewarderDistributor {
    using BitMaps for BitMaps.BitMap;

    address public immutable owner = msg.sender;

    // mapping of token to distribution data
    mapping(IERC20 token => Distribution) public distributions;

    error StillDistributing();
    error InvalidRoot();
    error AlreadyClaimed();
    error InvalidProof();
    error NotEnoughTokensToDistribute();

    event NewDistribution(IERC20 token, uint256 batchNumber, bytes32 newMerkleRoot, uint256 totalAmount);

    // Getters
    function getRemaining(address token) external view returns (uint256) {
        return distributions[IERC20(token)].remaining;
    }

    function getNextBatchNumber(address token) external view returns (uint256) {
        return distributions[IERC20(token)].nextBatchNumber;
    }

    function getRoot(address token, uint256 batchNumber) external view returns (bytes32) {
        return distributions[IERC20(token)].roots[batchNumber];
    }

    // Create a new distribution, setting the new root and the total amount to be distributed
    //params: token - the token to be distributed
    //params: newRoot - the new merkle root for the distribution
    //params: amount - the total amount to be distributed
    function createDistribution(IERC20 token, bytes32 newRoot, uint256 amount) external {
        
        //cannot distribute 0 tokens
        if (amount == 0) revert NotEnoughTokensToDistribute();

        //zero address cannot be the merkle root
        if (newRoot == bytes32(0)) revert InvalidRoot();

        //cannot create new distribution if there is still a distribution ongoing/ remaining tokens
        if (distributions[token].remaining != 0) revert StillDistributing();

        //initialize total amount to be distributed as remaining amount
        distributions[token].remaining = amount;

        // batching the distribution
        uint256 batchNumber = distributions[token].nextBatchNumber;
        // set the new root for the batch
        distributions[token].roots[batchNumber] = newRoot;
        // increment the batch number
        distributions[token].nextBatchNumber++;

        //transfer the tokens from the sender to the contract
        SafeTransferLib.safeTransferFrom(address(token), msg.sender, address(this), amount);

        emit NewDistribution(token, batchNumber, newRoot, amount);
    }

    // Clean up the contract by transferring out any remaining tokens
    function clean(IERC20[] calldata tokens) external {
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20 token = tokens[i];
            // if all tokens have been distributed, transfer the remaining tokens to the owner
            if (distributions[token].remaining == 0) {
                // transfer the remaining tokens to the owner
                token.transfer(owner, token.balanceOf(address(this)));
            }
        }
    }

    // Allow claiming rewards of multiple tokens in a single transaction
    function claimRewards(Claim[] memory inputClaims, IERC20[] memory inputTokens) external {
        Claim memory inputClaim;
        IERC20 token;
        uint256 bitsSet; // accumulator
        uint256 amount;

        // for each claim
        for (uint256 i = 0; i < inputClaims.length; i++) {

            inputClaim = inputClaims[i];
            // get the word position and bit position
            uint256 wordPosition = inputClaim.batchNumber / 256;
            uint256 bitPosition = inputClaim.batchNumber % 256;
            // get the token
            if (token != inputTokens[inputClaim.tokenIndex]) {
                if (address(token) != address(0)) {
                    if (!_setClaimed(token, amount, wordPosition, bitsSet)) revert AlreadyClaimed();
                }

                token = inputTokens[inputClaim.tokenIndex];
                bitsSet = 1 << bitPosition; // set bit at given position
                amount = inputClaim.amount;
            } else {
                bitsSet = bitsSet | 1 << bitPosition;
                amount += inputClaim.amount;
            }

            // for the last claim , this is vulnerable because someone can repeatedly claim  their valid claims in this array
            if (i == inputClaims.length - 1) {
                if (!_setClaimed(token, amount, wordPosition, bitsSet)) revert AlreadyClaimed();
            }

            bytes32 leaf = keccak256(abi.encodePacked(msg.sender, inputClaim.amount));
            bytes32 root = distributions[token].roots[inputClaim.batchNumber];

            if (!MerkleProof.verify(inputClaim.proof, root, leaf)) revert InvalidProof();

            inputTokens[inputClaim.tokenIndex].transfer(msg.sender, inputClaim.amount);
        }
    }

    function _setClaimed(IERC20 token, uint256 amount, uint256 wordPosition, uint256 newBits) private returns (bool) {
        uint256 currentWord = distributions[token].claims[msg.sender][wordPosition];
        if ((currentWord & newBits) != 0) return false;

        // update state
        distributions[token].claims[msg.sender][wordPosition] = currentWord | newBits;
        distributions[token].remaining -= amount;

        return true;
    }
}
