// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../node_modules/@openzeppelin/contracts/utils/Counters.sol";
import "../node_modules/@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "../node_modules/@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../node_modules/@openzeppelin/contracts/access/Ownable.sol";

/*
 * Smart contract allowing users to trade (list and buy) any ERC1155 tokens.
 * Users can create public and private listings.
 * Users can set more addresses that can buy tokens (like whitelist).
 */


contract Marketplace is Ownable, ReentrancyGuard{

    using Counters for Counters.Counter;
    Counters.Counter private _listingIds;
    Counters.Counter private _numOfTxs;
    uint256 private _volume;

    event TokenListed(address contractAddress, address seller, uint256 tokenId, uint256 amount, uint256 pricePerToken, bool privateSale);
    event TokenSold(address contractAddress, address seller, address buyer, uint256 tokenId, uint256 amount, uint256 pricePerToken, bool privateSale);

    mapping(uint256 => Listing) private idToListing;

    struct Listing {
        address contractAddress;
        address seller;
        address[] buyer;
        uint256 tokenId;
        uint256 amount;
        uint256 price;
        uint256 tokensAvailable;
        bool privateListing;
        bool completed;
    }

    struct Stats {
        uint256 volume;
        uint256 itemsSold;
    }


    function listToken(address contractAddress, uint256 tokenId, uint256 amount, uint256 price, address[] memory privateBuyer) public nonReentrant {
        ERC1155 token = ERC1155(contractAddress);

        require(token.balanceOf(msg.sender, tokenId) > amount, "Caller must own given token!");
        require(token.isApprovedForAll(msg.sender, address(this)), "Contract must be approved!");

        bool privateListing = privateBuyer.length>0;
        _listingIds.increment();
        uint256 listingId = _listingIds.current();
        idToListing[listingId] = Listing(contractAddress, msg.sender, privateBuyer, tokenId, amount, price, amount, privateListing, false);

        emit TokenListed(contractAddress, msg.sender, tokenId, amount, price, privateListing);
    }

    function purchaseToken(uint256 listingId, uint256 amount) public payable nonReentrant {
        ERC1155 token = ERC1155(idToListing[listingId].contractAddress);

        if(idToListing[listingId].privateListing == true) {
            bool whitelisted = false;
            for(uint i=0; i<idToListing[listingId].buyer.length; i++){
                if(idToListing[listingId].buyer[i] == msg.sender) {
                    whitelisted = true;
                }
            }
            require(whitelisted == true, "Sale is private!");
        }

        require(msg.sender != idToListing[listingId].seller, "Can't buy your onw tokens!");
        require(msg.value >= idToListing[listingId].price * amount, "Insufficient funds!");
        require(token.balanceOf(idToListing[listingId].seller, idToListing[listingId].tokenId) >= amount, "Seller doesn't have enough tokens!");
        require(idToListing[listingId].completed == false, "Listing not available anymore!");
        require(idToListing[listingId].tokensAvailable >= amount, "Not enough tokens left!");
        
        _numOfTxs.increment();
        _volume += idToListing[listingId].price * amount;

        idToListing[listingId].tokensAvailable -= amount;
        if(idToListing[listingId].privateListing == false){
            idToListing[listingId].buyer.push(msg.sender);
        }
        if(idToListing[listingId].tokensAvailable == 0) {
            idToListing[listingId].completed = true;
        }

        emit TokenSold(
            idToListing[listingId].contractAddress,
            idToListing[listingId].seller,
            msg.sender,
            idToListing[listingId].tokenId,
            amount,
            idToListing[listingId].price,
            idToListing[listingId].privateListing
        );

        token.safeTransferFrom(idToListing[listingId].seller, msg.sender, idToListing[listingId].tokenId, amount, "");
        payable(idToListing[listingId].seller).transfer((idToListing[listingId].price * amount/50)*49); //Transfering 98% to seller, fee 2%  ((msg.value/50)*49)
    }

    function  viewAllListings() public view returns (Listing[] memory) {
        uint itemCount = _listingIds.current();
        uint unsoldItemCount = _listingIds.current() - _numOfTxs.current();
        uint currentIndex = 0;

        Listing[] memory items = new Listing[](unsoldItemCount);
        for (uint i = 0; i < itemCount; i++) {
                uint currentId = i + 1;
                Listing storage currentItem = idToListing[currentId];
                items[currentIndex] = currentItem;
                currentIndex += 1;
        }

        return items;
    }

    function viewListingById(uint256 _id) public view returns(Listing memory) {
        return idToListing[_id];
    }

    function viewStats() public view returns(Stats memory) {
        return Stats(_volume, _numOfTxs.current());
    }

    function withdrawFees() public onlyOwner nonReentrant {
        payable(msg.sender).transfer(address(this).balance);
    }

}