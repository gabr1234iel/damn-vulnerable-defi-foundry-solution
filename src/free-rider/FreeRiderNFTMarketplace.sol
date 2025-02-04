// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {DamnValuableNFT} from "../DamnValuableNFT.sol";

contract FreeRiderNFTMarketplace is ReentrancyGuard {   

    using Address for address payable;

    DamnValuableNFT public token;   // NFT contract
    uint256 public offersCount;     // number of active offers

    // tokenId -> price
    mapping(uint256 => uint256) private offers;     //maps token id to price

    event NFTOffered(address indexed offerer, uint256 tokenId, uint256 price);      // event for NFT offer
    event NFTBought(address indexed buyer, uint256 tokenId, uint256 price);         // event for NFT buy

    error InvalidPricesAmount();
    error InvalidTokensAmount();
    error InvalidPrice();
    error CallerNotOwner(uint256 tokenId);
    error InvalidApproval();
    error TokenNotOffered(uint256 tokenId);
    error InsufficientPayment();

    constructor(uint256 amount) payable {
        DamnValuableNFT _token = new DamnValuableNFT();
        _token.renounceOwnership();
        for (uint256 i = 0; i < amount;) {
            _token.safeMint(msg.sender);
            unchecked {
                ++i;
            }
        }
        token = _token;
    }

    function offerMany(uint256[] calldata tokenIds, uint256[] calldata prices) external nonReentrant {
        uint256 amount = tokenIds.length;
        if (amount == 0) {
            revert InvalidTokensAmount();
        }

        if (amount != prices.length) {
            revert InvalidPricesAmount();
        }

        for (uint256 i = 0; i < amount; ++i) {
            unchecked {
                _offerOne(tokenIds[i], prices[i]);
            }
        }
    }

    function _offerOne(uint256 tokenId, uint256 price) private {
        DamnValuableNFT _token = token; // gas savings

        if (price == 0) {
            revert InvalidPrice();
        }

        if (msg.sender != _token.ownerOf(tokenId)) {
            revert CallerNotOwner(tokenId);
        }

        if (_token.getApproved(tokenId) != address(this) && !_token.isApprovedForAll(msg.sender, address(this))) {
            revert InvalidApproval();
        }

        offers[tokenId] = price;

        assembly {
            // gas savings
            sstore(0x02, add(sload(0x02), 0x01))
        }

        emit NFTOffered(msg.sender, tokenId, price);
    }

    function buyMany(uint256[] calldata tokenIds) external payable nonReentrant {
        for (uint256 i = 0; i < tokenIds.length; ++i) {
            unchecked {
                _buyOne(tokenIds[i]);
            }
        }
    }


    function _buyOne(uint256 tokenId) private {
        uint256 priceToPay = offers[tokenId];
        if (priceToPay == 0) {
            revert TokenNotOffered(tokenId);
        }

        if (msg.value < priceToPay) {
            revert InsufficientPayment();
        }   

        // exploit here, because the price is checked within the buyMany loop, we can flashswap the eth from uniswap pair, pay the price of 1 nft to buy all...
        // we can send the nfts we get to the recovery manager to get paid 45eth to repay the initial flash swap 'loan'

        --offersCount;

        // transfer from seller to buyer
        DamnValuableNFT _token = token; // cache for gas savings
        _token.safeTransferFrom(_token.ownerOf(tokenId), msg.sender, tokenId);          
        // nft is transferred from seller to buyer using safeTransferFrom
        // new owner is msg.sender(buyer)
        

        // pay seller using cached token
        payable(_token.ownerOf(tokenId)).sendValue(priceToPay);

        // the contract call sendValue to the wrong recipient (_token.ownerOf(tokenId)) which at this time it's the msg.sender (buyer)
        // since the nft was transferred to him right before this call. The 15 ETH will go back to the buyer because of this which will allow him to 
        // basically pay 15 ETH for all available nfts.
        // the contract should have used the owner of the contract as the recipient of the 15 ETH or like previous owner instead of current owner.

        emit NFTBought(msg.sender, tokenId, priceToPay);
    }

    receive() external payable {}
}
