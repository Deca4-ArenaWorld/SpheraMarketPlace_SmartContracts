// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";

contract SpheraToken is ERC20, Ownable2Step {
    constructor(string memory _name, string memory _symbol, uint256 _supply) Ownable(msg.sender) ERC20(_name, _symbol) {
        _mint(msg.sender, _supply * 10 ** decimals());
    }

    function mint(address _to, uint256 _amount) external onlyOwner{
        _mint(_to, _amount);
    }
}
