// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";

contract SpheraPoints is ERC20, Ownable2Step() {
    mapping(address => bool) internal minterRole;
    event AddedMinterRole(address indexed minter, uint256 indexed timestamp);
    event RevokedMinterRole(address indexed minter, uint256 indexed timestamp);

    constructor(
        string memory _name,
        string memory _symbol
    ) Ownable(msg.sender) ERC20(_name, _symbol) {}

    function setMinterRoleAddress(address _address) external onlyOwner {
        minterRole[_address] = true;
        emit AddedMinterRole(_address, block.timestamp);
    }

    function mint(address _to, uint256 _amount) external {
        require(
            minterRole[msg.sender],
            "Only Minters are allowed to mint tokens"
        );
        _mint(_to, _amount * 10 ** decimals());
    }

    function revokeMinterRole(address _address) external onlyOwner {
        require(minterRole[_address], "Address is not a minter");
        minterRole[_address] = false;
        emit RevokedMinterRole(_address, block.timestamp);
    }
}
