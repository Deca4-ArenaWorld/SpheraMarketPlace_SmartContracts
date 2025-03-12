// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SpheraNFTCollection is
    ERC721,
    ERC721URIStorage,
    ERC721Burnable,
    Ownable
{
    uint256 public nextTokenId = 1;

    constructor(string memory name, string memory symbol)
        ERC721(name, symbol)
        Ownable(msg.sender)
    {}

    function safeMint(address to, string memory uri)
        public
        onlyOwner
        returns (uint256)
    {
        uint256 tokenId = nextTokenId++;
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);

        return tokenId;
    }

    function batchMint(address[] memory to, string[] memory uri)
        public
        onlyOwner
        returns (uint256[] memory)
    {
        require(to.length == uri.length, "Mismatched array lengths");
        uint256[] memory tokenIds = new uint256[](to.length);

        for (uint256 i = 0; i < to.length; i++) {
            uint256 tokenId = nextTokenId++;
            _safeMint(to[i], tokenId);
            _setTokenURI(tokenId, uri[i]);
            tokenIds[i] = tokenId;
        }

        return tokenIds;
    }

    function batchBurn(uint256[] memory tokenIds) public onlyOwner {
        require(tokenIds.length < 100, "Burn limit exceeded");

        for (uint256 i = 0; i < tokenIds.length; i++) {
            _burn(tokenIds[i]);
        }
    }

    function burn(uint256 tokenId) public override onlyOwner {
        _burn(tokenId);
    }

    function batchTransfer(
        address[] memory recipients,
        uint256[] memory tokenIds
    ) public {
        require(
            recipients.length == tokenIds.length,
            "Mismatched array lengths"
        );

        for (uint256 i = 0; i < tokenIds.length; i++) {
            require(
                ownerOf(tokenIds[i]) == msg.sender,
                "Caller is not token owner"
            );
            _transfer(msg.sender, recipients[i], tokenIds[i]);
        }
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
