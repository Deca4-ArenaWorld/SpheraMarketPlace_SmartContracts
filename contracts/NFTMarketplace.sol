// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Royalty.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

interface ISPoint is IERC20 {
    function mint(address _to, uint _amount) external;
}

contract NFTMarketplace is ERC2981, Pausable  {
    enum MarketResponseCodes {
        SUCCESS,
        CONTRACT_DOES_NOT_HAVE_ALLOWANCE,
        NOT_THE_CONTRACT_OWNER,
        BID_NOT_EXISTS,
        NOT_ENOUGH_MONEY,
        TOKEN_ASSOCIATION_FAILED,
        WRONG_PAGINATION,
        WRONG_FUNCTION_INPUTS,
        NFT_ALREADY_LISTED,
        NO_PERMISSION,
        ALLOWANCE_REQUIRED,
        NFT_INFO_FETCH_FAILED,
        NFT_NOT_LISTED,
        NFT_TRANSFER_FAILED,
        SPH_TRANSFER_FAILED
    }

    //////////// EVENTS /////////////
    event ListNFT(
        address indexed token,
        uint indexed serialNumber,
        address indexed _owner,
        uint price
    );
    event UnlistNFT(
        address indexed token,
        uint indexed serialNumber,
        address indexed owner,
        uint price
    );
    event AddBid(
        address indexed token,
        uint serialNumber,
        address indexed owner,
        address indexed buyer,
        uint amount
    );
    event DeleteBid(
        address indexed token,
        uint indexed serialNumber,
        address indexed owner,
        uint amount
    );
    event AcceptBid(
        address indexed token,
        uint serialNumber,
        address indexed owner,
        address indexed buyer,
        uint acceptedBidAmount
    );

    uint public sPoint4Buy = 200;
    uint public sPoint4List = 10;
    uint public sPoint4Bid = 100;

    address public sPointAddress;

    ///////// STRUCTURES ////////////
    struct Bid {
        address payable owner;
        uint amount;
        address token;
        uint serialNumber;
    }

    struct BidIndexes {
        uint tokenIndex;
        uint receivedIndex;
        uint sentIndex;
        bool isSet;
    }

    struct BuyerTokens {
        uint sphs;
    }

    // Struct to hold NFT details
    struct NFT {
        address payable owner;
        uint price;
        address token;
        uint serialNumber;
        bool isListed;
    }

    struct NonFungibleTokenInfo {
        address owner;
        address spender;
    }

    ////////// VARIABLES ////////////

    // Mapping to store bids for each buyer
    mapping(string => Bid[]) public tokenBids;
    // Store bids maps for fast getting
    mapping(address => Bid[]) public receivedBids;
    mapping(address => Bid[]) public sentBids;

    mapping(address => mapping(string => BidIndexes)) public buyersBidsIndexes;
    mapping(address => BuyerTokens) public buyersTokens;
    // Mapping from NFT to its details
    // Key format: "EVM_TOKEN_ID/SERIAL_NUMBER"
    mapping(string => NFT) public nfts;
    address internal contractOwner;

    IERC20 public spheraTokenAddress;
    address public treasuryWalletAddress;
    uint public taxFee = 250;

    modifier onlyContractOwner() {
        require(msg.sender == contractOwner, "Not the contract owner");
        _;
    }

    constructor() {
        contractOwner = msg.sender;
    }

    receive() external payable {}

    fallback() external payable {}

    //////////// INTERNAL ///////////

    function removeBidInfo(string memory nftId, address _buyer) internal {
        address nftOwner = nfts[nftId].owner;
        require(
            buyersBidsIndexes[_buyer][nftId].isSet,
            "There is no bid, you can't remove it"
        );

        BidIndexes memory indexes = buyersBidsIndexes[_buyer][nftId];

        // Iterate through each bid type (token, sent, received)
        for (uint8 bidType = 0; bidType < 3; bidType++) {
            Bid[] storage bidArray;
            uint bidIndex;

            // Determine the bid array and index based on bid type
            if (bidType == 0) {
                bidArray = tokenBids[nftId];
                bidIndex = indexes.tokenIndex;
            } else if (bidType == 1) {
                bidArray = sentBids[_buyer];
                bidIndex = indexes.sentIndex;
            } else {
                bidArray = receivedBids[nftOwner];
                bidIndex = indexes.receivedIndex;
            }

            // Move the last element to the position of the element to be removed
            uint lastIndex = bidArray.length - 1;
            Bid memory bidToMove = bidArray[lastIndex];
            bidArray[bidIndex] = bidToMove;

            // Remove the last element by reducing the length of the array
            bidArray.pop();

            // Determine the bid array and index based on bid type
            if (bidType == 0) {
                buyersBidsIndexes[bidToMove.owner][nftId].tokenIndex = bidIndex;
            } else if (bidType == 1) {
                buyersBidsIndexes[bidToMove.owner][nftId].sentIndex = bidIndex;
            } else {
                buyersBidsIndexes[bidToMove.owner][nftId]
                    .receivedIndex = bidIndex;
            }
        }

        /////// FINAL ///////

        // Remove pointer for removed bid
        buyersBidsIndexes[_buyer][nftId].isSet = false;
    }

    function registerSpheraToken(
        address _tokenAddress
    ) public onlyContractOwner {
        spheraTokenAddress = IERC20(_tokenAddress);
    }

    function setTreasuryWalletAddress(
        address _walletAddress
    ) public onlyContractOwner {
        treasuryWalletAddress = _walletAddress;
    }

    function sendSphs(address sender, address recipient, uint amount) internal {
        require(
            buyersTokens[sender].sphs >= amount,
            "Not enough user sphs on the contract!"
        );

        IERC20(spheraTokenAddress).transfer(recipient, amount);

        if (sender != address(this)) {
            buyersTokens[sender].sphs -= amount;
        }
    }

    // acceptedBuyer address(0) = return money to everybody
    function removeBids(
        string memory nftId,
        address moneyBackException
    ) internal {
        int index = int(tokenBids[nftId].length) - 1;

        while (index >= 0) {
            uint _index = uint(index);
            Bid memory bid = tokenBids[nftId][_index];

            // return money from bid
            if (bid.owner != moneyBackException) {
                sendSphs(bid.owner, bid.owner, bid.amount);
            }

            removeBidInfo(nftId, bid.owner);

            index = int(tokenBids[nftId].length) - 1;
        }
    }

    function addressToString(
        address _addr
    ) internal pure returns (string memory) {
        bytes32 value = bytes32(uint(uint160(_addr)));
        bytes memory alphabet = "0123456789abcdef";

        bytes memory str = new bytes(42);
        str[0] = "0";
        str[1] = "x";

        for (uint i = 0; i < 20; i++) {
            str[2 + i * 2] = alphabet[uint8(value[i + 12] >> 4)];
            str[3 + i * 2] = alphabet[uint8(value[i + 12] & 0x0f)];
        }
        return string(str);
    }

    function uint256ToString(uint _num) internal pure returns (string memory) {
        if (_num == 0) {
            return "0";
        }

        uint num = _num;
        uint digits = 0;
        uint tempNum = num;

        while (tempNum != 0) {
            digits++;
            tempNum /= 10;
        }

        bytes memory buffer = new bytes(digits);

        uint index = digits;

        while (num != 0) {
            index--;
            buffer[index] = bytes1(uint8(48 + (num % 10)));
            num /= 10;
        }

        return string(buffer);
    }

    function concatenateAddressAndInt(
        address _addr,
        uint _num
    ) internal pure returns (string memory) {
        string memory addressString = addressToString(_addr);
        string memory intString = uint256ToString(_num);

        return string(abi.encodePacked(addressString, "/", intString));
    }

    function formatNftId(
        address _token,
        uint _serialNumber
    ) internal pure returns (string memory) {
        return concatenateAddressAndInt(_token, _serialNumber);
    }

    function getPaginatedBids(
        Bid[] memory bidArray,
        uint64 page,
        uint64 pageSize
    ) private pure returns (Bid[] memory) {
        if (bidArray.length == 0) {
            return bidArray;
        }

        require(pageSize > 0, "pageSize must be greater than 0");
        require(page > 0, "pagination is starting at 1");

        uint startIndex = (page - 1) * pageSize;
        require(startIndex < bidArray.length, "Page out of bounds");

        uint endIndex = startIndex + pageSize;
        if (endIndex > bidArray.length) {
            endIndex = bidArray.length;
        }

        Bid[] memory pageBids = new Bid[](endIndex - startIndex);

        for (uint i = startIndex; i < endIndex; i++) {
            pageBids[i - startIndex] = bidArray[i];
        }

        return pageBids;
    }

    //////////// PUBLIC /////////////
    function registerSPointAddress(
        address _sPointAddress
    ) public onlyContractOwner {
        sPointAddress = _sPointAddress;
    }

    function getTokenBid(
        address _token,
        uint _serialNumber,
        address _buyer
    ) public view returns (Bid memory) {
        string memory nftId = formatNftId(_token, _serialNumber);

        Bid memory bid = Bid({
            amount: 0,
            owner: payable(_buyer),
            token: _token,
            serialNumber: _serialNumber
        });

        BidIndexes memory bidIndex = buyersBidsIndexes[_buyer][nftId];

        if (!bidIndex.isSet) {
            return bid;
        }

        return tokenBids[nftId][bidIndex.tokenIndex];
    }

    function getTokenBids(
        address _token,
        uint _serialNumber,
        uint64 page,
        uint64 pageSize
    ) public view returns (Bid[] memory) {
        string memory nftId = formatNftId(_token, _serialNumber);
        Bid[] memory allBids = tokenBids[nftId];

        return getPaginatedBids(allBids, page, pageSize);
    }

    function getReceivedBids(
        address _owner,
        uint64 page,
        uint64 pageSize
    ) public view returns (Bid[] memory) {
        Bid[] memory allBids = receivedBids[_owner];

        return getPaginatedBids(allBids, page, pageSize);
    }

    function getSentBids(
        address _buyer,
        uint64 page,
        uint64 pageSize
    ) public view returns (Bid[] memory) {
        Bid[] memory allBids = sentBids[_buyer];

        return getPaginatedBids(allBids, page, pageSize);
    }

    function getNonFungibleTokenInfo(
        address _token,
        uint _id
    ) internal view returns (NonFungibleTokenInfo memory) {
        IERC721 nftContract = IERC721(_token);
        NonFungibleTokenInfo memory tokenInfo = NonFungibleTokenInfo({
            owner: nftContract.ownerOf(_id),
            spender: nftContract.getApproved(_id)
        });
        return tokenInfo;
    }

    ////////// NFT OWNER ////////////

    function listNFT(
        address[] memory _tokens,
        uint[] memory _serialNumbers,
        uint[] memory _prices
    ) external returns (uint) {
        require(
            _tokens.length > 0 &&
                _serialNumbers.length > 0 &&
                _prices.length > 0,
            "Array length should be more than 0"
        );
        require(
            _tokens.length == _serialNumbers.length &&
                _tokens.length == _prices.length,
            "Arrays length mismatch"
        );

        for (uint i = 0; i < _tokens.length; i++) {
            address _token = _tokens[i];
            uint _serialNumber = _serialNumbers[i];
            uint _price = _prices[i];

            NonFungibleTokenInfo memory tokenInfo = getNonFungibleTokenInfo(
                _token,
                _serialNumber
            );

            require(
                tokenInfo.spender == address(this),
                "The Contract doesn't have allowance for this token"
            );
            require(
                msg.sender == tokenInfo.owner,
                "You have no permission for this function"
            );

            string memory nftId = formatNftId(_token, _serialNumber);

            if (nfts[nftId].isListed && nfts[nftId].owner != tokenInfo.owner) {
                removeBids(nftId, address(0));
            }

            nfts[nftId] = NFT({
                owner: payable(tokenInfo.owner),
                price: _price,
                token: _token,
                serialNumber: _serialNumber,
                isListed: true
            });

            emit ListNFT(_token, _serialNumber, msg.sender, _price);

            Bid memory maxAmountBid;
            for (uint j = 0; j < tokenBids[nftId].length; j++) {
                Bid memory bid = tokenBids[nftId][j];

                if (
                    bid.amount >= nfts[nftId].price &&
                    bid.amount > maxAmountBid.amount
                ) {
                    maxAmountBid = bid;
                    break;
                }
            }

            if (maxAmountBid.amount != 0) {
                this.acceptBid(
                    _token,
                    _serialNumber,
                    maxAmountBid.owner,
                    maxAmountBid.amount
                );
            }
        }

        ISPoint(sPointAddress).mint(msg.sender, sPoint4List);

        return uint(MarketResponseCodes.SUCCESS);
    }

    function unlistNFT(
        address _token,
        uint _serialNumber
    ) external whenNotPaused returns (uint) {
        string memory nftId = formatNftId(_token, _serialNumber);

        NonFungibleTokenInfo memory tokenInfo = getNonFungibleTokenInfo(
            _token,
            _serialNumber
        );

        require(
            msg.sender == tokenInfo.owner || msg.sender == contractOwner,
            "You have no permission for this function"
        );

        removeBids(nftId, address(0));

        nfts[nftId].isListed = false;

        emit UnlistNFT(
            _token,
            _serialNumber,
            tokenInfo.owner,
            nfts[nftId].price
        );
        return uint(MarketResponseCodes.SUCCESS);
    }

    function acceptBid(
        address _token,
        uint _serialNumber,
        address payable _buyer,
        uint _acceptedBidAmount
    ) external whenNotPaused returns (uint) {
        string memory nftId = formatNftId(_token, _serialNumber);

        require(
            msg.sender == nfts[nftId].owner || msg.sender == address(this),
            "You have no permission for this function"
        );
        require(nfts[nftId].isListed, "NFT not listed");

        NonFungibleTokenInfo memory nftInfo = getNonFungibleTokenInfo(
            _token,
            _serialNumber
        );

        require(
            nftInfo.spender == address(this),
            "Contract doesn't have allowance for this NFT"
        );
        require(
            buyersBidsIndexes[_buyer][nftId].isSet,
            "Buyer doesn't have bid for this NFT"
        );
        require(
            tokenBids[nftId][buyersBidsIndexes[_buyer][nftId].tokenIndex]
                .amount == _acceptedBidAmount,
            "This buyer didn't suggest that price value for this NFT"
        );
        require(
            buyersTokens[_buyer].sphs >= _acceptedBidAmount,
            "Buyer doesn't have enough SPHs in the contract"
        );

        uint ownerRewardAmount = _acceptedBidAmount;

        if (taxFee > 0) {
            uint taxAmount = (ownerRewardAmount * taxFee) / 10000;

            require(
                treasuryWalletAddress != address(0),
                "Treasury wallet address not set up."
            );
            IERC20(spheraTokenAddress).transfer(
                treasuryWalletAddress,
                taxAmount
            );

            ownerRewardAmount -= taxAmount;
        }
        if (checkIfSupportsERC2981(_token)) {
            (address receiver, uint256 royaltyAmount) = ERC721Royalty(_token)
                .royaltyInfo(_serialNumber, ownerRewardAmount);
            IERC20(spheraTokenAddress).transfer(receiver, royaltyAmount);

            ownerRewardAmount -= royaltyAmount;
        }

        sendSphs(_buyer, nfts[nftId].owner, ownerRewardAmount);

        IERC721(_token).safeTransferFrom(
            nfts[nftId].owner,
            _buyer,
            _serialNumber
        );
        removeBids(nftId, _buyer);

        emit AcceptBid(
            _token,
            _serialNumber,
            nfts[nftId].owner,
            _buyer,
            _acceptedBidAmount
        );

        nfts[nftId].isListed = false;
        nfts[nftId].owner = _buyer;

        ISPoint(sPointAddress).mint(_buyer, sPoint4Buy);

        return uint(MarketResponseCodes.SUCCESS);
    }

    ///////////// BUYER /////////////
    function addBids(
        address[] memory _tokens,
        uint[] memory _serialNumbers,
        uint[] memory tokenAmounts
    ) external whenNotPaused returns (uint[] memory) {
        require(
            _tokens.length == _serialNumbers.length &&
                _tokens.length == tokenAmounts.length,
            "Invalid data."
        );
        uint[] memory results = new uint[](_tokens.length);
        for (uint i = 0; i < _tokens.length; i++) {
            results[i] = addBid(_tokens[i], _serialNumbers[i], tokenAmounts[i]);
        }
        return results;
    }

    function addBid(
        address _token,
        uint _serialNumber,
        uint tokenAmount
    ) public whenNotPaused returns (uint) {
        address payable _buyer = payable(msg.sender);
        string memory nftId = formatNftId(_token, _serialNumber);

        require(nfts[nftId].isListed, "NFT not listed");

        NonFungibleTokenInfo memory nftInfo = getNonFungibleTokenInfo(
            _token,
            _serialNumber
        );

        require(
            nftInfo.owner == nfts[nftId].owner,
            "Nft owner has been changed. Invalid NFT listing."
        );
        IERC20(spheraTokenAddress).transferFrom(
            msg.sender,
            address(this),
            tokenAmount
        );
        if (buyersTokens[_buyer].sphs == 0) {
            buyersTokens[_buyer] = BuyerTokens({sphs: tokenAmount});
        } else {
            buyersTokens[_buyer].sphs += tokenAmount;
        }

        BidIndexes memory prevBidIndex = buyersBidsIndexes[_buyer][nftId];

        if (buyersBidsIndexes[_buyer][nftId].isSet) {
            Bid memory _previousBid = tokenBids[nftId][prevBidIndex.tokenIndex];

            sendSphs(_buyer, _buyer, _previousBid.amount);

            tokenBids[nftId][prevBidIndex.tokenIndex].amount = tokenAmount;
            receivedBids[nfts[nftId].owner][prevBidIndex.receivedIndex]
                .amount = tokenAmount;
            sentBids[_buyer][prevBidIndex.sentIndex].amount = tokenAmount;

            if (tokenAmount >= nfts[nftId].price) {
                return
                    this.acceptBid(_token, _serialNumber, _buyer, tokenAmount);
            }

            emit AddBid(
                _token,
                _serialNumber,
                nftInfo.owner,
                msg.sender,
                tokenAmount
            );
            return uint(MarketResponseCodes.SUCCESS);
        }

        // add bid and save its index
        Bid memory bid = Bid({
            amount: tokenAmount,
            owner: _buyer,
            token: _token,
            serialNumber: _serialNumber
        });

        tokenBids[nftId].push(bid);
        sentBids[msg.sender].push(bid);
        receivedBids[nfts[nftId].owner].push(bid);

        buyersBidsIndexes[_buyer][nftId] = BidIndexes({
            tokenIndex: tokenBids[nftId].length - 1,
            sentIndex: sentBids[msg.sender].length - 1,
            receivedIndex: receivedBids[nfts[nftId].owner].length - 1,
            isSet: true
        });

        if (tokenAmount >= nfts[nftId].price) {
            return this.acceptBid(_token, _serialNumber, _buyer, bid.amount);
        }

        emit AddBid(
            _token,
            _serialNumber,
            nftInfo.owner,
            msg.sender,
            tokenAmount
        );

        ISPoint(sPointAddress).mint(msg.sender, sPoint4Bid);

        return uint(MarketResponseCodes.SUCCESS);
    }

    function deleteBid(
        address _token,
        uint _serialNumber,
        address payable _buyer
    ) external whenNotPaused returns (uint) {
        string memory nftId = formatNftId(_token, _serialNumber);

        require(
            msg.sender == _buyer || msg.sender == contractOwner,
            "You have no permissions for this function."
        );
        require(
            buyersBidsIndexes[_buyer][nftId].isSet,
            "You have no bids for this NFT"
        );

        uint bidTokenIndex = buyersBidsIndexes[_buyer][nftId].tokenIndex;
        Bid memory bid = tokenBids[nftId][bidTokenIndex];

        require(
            buyersTokens[_buyer].sphs >= tokenBids[nftId][bidTokenIndex].amount,
            "You have no enough money in the contract to delete bid"
        );

        emit DeleteBid(_token, _serialNumber, msg.sender, bid.amount);

        sendSphs(_buyer, _buyer, bid.amount);
        removeBidInfo(nftId, bid.owner);

        return uint(MarketResponseCodes.SUCCESS);
    }

    function changeTaxFee(uint _newFee) public onlyContractOwner {
        taxFee = _newFee;
    }

    function checkIfSupportsERC2981(
        address nftAddress
    ) public view returns (bool) {
        bytes4 interfaceId = 0x2a55205a;
        return IERC165(nftAddress).supportsInterface(interfaceId);
    }

    function changePoints(
        uint256 _sPoint4Buy,
        uint256 _sPoint4List,
        uint256 _sPoint4Bid
    ) public onlyContractOwner {
        sPoint4Buy = _sPoint4Buy;
        sPoint4List = _sPoint4List;
        sPoint4Bid = _sPoint4Bid;
    }

    function unpause() external onlyContractOwner {
        _unpause();
    }

    function pause() external onlyContractOwner {
        _pause();
    }
}
