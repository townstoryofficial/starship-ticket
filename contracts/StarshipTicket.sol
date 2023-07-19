// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract StarshipTicket is ERC721, ERC2981, ERC721Enumerable, Pausable, AccessControl, ERC721Burnable, ReentrancyGuard {
    using Strings for uint256;
    using Counters for Counters.Counter;

    enum Status {
        WhiteListSale,
        PublicSale
    }

    uint256 public openSupply;

    string private baseURI;
    string private baseExtension;

    bytes32 public merkleRoot;
    address public tokenContract;
    uint256 public saleEthPrice;
    uint256 public saleArbPrice;

    uint8 public phase;
    uint256 public saleStartTime;

    mapping(Status => uint256) public mintMax;
    mapping(Status => uint256) public mintCount;
    mapping(Status => uint256) public mintPerMax;

    mapping(uint8 => uint256) public whiteListPhaseCount;
    mapping(address => mapping(uint8 => bool)) private whiteList;

    mapping(address => mapping(uint8 => uint256)) public amountMintedPerWhiteList;
    mapping(address => mapping(uint8 => uint256)) public amountMintedPerPublic;

    Counters.Counter private _tokenIdCounter;
    bytes32 public constant SERVER_ROLE = keccak256("SERVER_ROLE");

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _startId,
        uint256 _startTime,
        address _serverRole,
        address _tokenContract
    ) ERC721(_name, _symbol) {
        _tokenIdCounter._value = _startId;
        _setDefaultRoyalty(msg.sender, 500);
        _grantRole(SERVER_ROLE, _serverRole);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        
        setPhase(1);
        setSaleStartTime(_startTime);
        setTokenContract(_tokenContract);
        setSaleEthPrice(1000000000000000000);
        setSaleArbPrice(10000000000000000000);

        setOpenSupply(10000);
        setMintMax(Status.WhiteListSale, 2500);
        setMintMax(Status.PublicSale, 7500);
        setMintPerMax(Status.WhiteListSale, 1);
        setMintPerMax(Status.PublicSale, 5);
    }

    modifier _notContract() {
        uint256 size;
        address addr = msg.sender;
        assembly {
            size := extcodesize(addr)
        }
        require(size == 0, "Contract is not allowed");
        require(msg.sender == tx.origin, "Proxy contract is not allowed");
        _;
    }
    
    modifier _saleStartTime(uint256 _startTime) {
        require(currentTime() >= _startTime, "Sale has not started yet");
        _;
    }

    function mint() 
        public
        payable
        whenNotPaused
        _notContract
        _saleStartTime(saleStartTime)
        nonReentrant
    {
        require(msg.value >= saleEthPrice, "Not enough funds");
        _mintBatch(msg.sender, 1);
    }

    function publicMint(uint256 amount) 
        public
        whenNotPaused
        _notContract
        _saleStartTime(saleStartTime)
        nonReentrant
    {
        Status _current = Status.PublicSale;
        require(amountMintedPerPublic[msg.sender][phase] + amount <= mintPerMax[_current], "Minted reached the limit");
        require(mintCount[_current] + amount <= mintMax[_current], "Exceeded max mint");

        IERC20 arb = IERC20(tokenContract);
        uint256 price = saleArbPrice * amount;
        require(arb.balanceOf(msg.sender) >= price, "Not enough funds");
        
        arb.transferFrom(msg.sender, address(this), price);

        mintCount[_current] += amount;
        amountMintedPerPublic[msg.sender][phase] += amount;
        _mintBatch(msg.sender, amount);
    }

    function whitelistMint(uint256 amount, bytes32[] calldata _merkleProof) 
        public
        whenNotPaused
        _notContract
        _saleStartTime(saleStartTime)
        nonReentrant
    {
        Status _current = Status.WhiteListSale;
        require(amountMintedPerWhiteList[msg.sender][phase] + amount <= mintPerMax[_current], "Minted reached the limit");
        require(mintCount[_current] + amount <= mintMax[_current], "Exceeded max mint");

        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
        if(!MerkleProof.verify(_merkleProof, merkleRoot, leaf)) {
            require(whiteList[msg.sender][phase], "Not in whitelist");
        }

        mintCount[_current] += amount;
        amountMintedPerWhiteList[msg.sender][phase] += amount;
        _mintBatch(msg.sender, amount);
    }

    function _mintBatch(address _to, uint256 _amount) internal {
        require(totalSupply() + _amount <= openSupply, "Exceeded the supply limit");

        for (uint256 i = 0; i < _amount; i++) {
            uint256 tokenId = _tokenIdCounter.current();
            _tokenIdCounter.increment();
            _safeMint(_to, tokenId);
        }
    }

    function rewardClaim(address[] memory addrs) public onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < addrs.length; i++) {
            _mintBatch(addrs[i], 1);
        }
    }

    function listOfBalances(address _address) public view returns (uint256[] memory) {
        uint256 balance = balanceOf(_address);
        uint256[] memory balances = new uint256[](balance);
        
        for (uint256 i = 0; i < balance; i++) {
            uint256 _tokenId = tokenOfOwnerByIndex(_address, i);
            balances[i] = _tokenId;
        }

        return balances;
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        _requireMinted(tokenId);
        string memory base = _baseURI();
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(base, tokenId.toString(), baseExtension)) : "";
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    // Whitelist
    function isWhiteList(address owner, uint8 _phase) public view returns (bool) {
        return whiteList[owner][_phase];
    }

    function addWhiteList(address[] memory addresses, uint8 _phase) public onlyRole(SERVER_ROLE) {
        for (uint i = 0; i < addresses.length; i++) {
            whiteListPhaseCount[_phase]++;
            whiteList[addresses[i]][_phase] = true;
        }
    }

    // Setting
    function pause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function setBaseURI(string memory _uri) public onlyRole(DEFAULT_ADMIN_ROLE) {
        baseURI = _uri;
    }

    function setSaleEthPrice(uint256 price) public onlyRole(DEFAULT_ADMIN_ROLE) {
        saleEthPrice = price;
    }

    function setSaleArbPrice(uint256 price) public onlyRole(DEFAULT_ADMIN_ROLE) {
        saleArbPrice = price;
    }

    function setTokenContract(address addr) public onlyRole(DEFAULT_ADMIN_ROLE) {
        tokenContract = addr;
    }

    function setSaleStartTime(uint256 startTime) public onlyRole(DEFAULT_ADMIN_ROLE) {
        saleStartTime = startTime;
    }

    function setBaseExtension(string memory _baseExtension) public onlyRole(DEFAULT_ADMIN_ROLE) {
        baseExtension = _baseExtension;
    }

    function setPhase(uint8 _phase) public onlyRole(DEFAULT_ADMIN_ROLE) {
        phase = _phase;
    }

    function setOpenSupply(uint256 _openSupply) public onlyRole(DEFAULT_ADMIN_ROLE) {
        openSupply = _openSupply;
    }

    function setMerkleRoot(bytes32 _merkleRoot) public onlyRole(DEFAULT_ADMIN_ROLE) {
        merkleRoot = _merkleRoot;
    }

    function setMintMax(Status _status, uint256 _max) public onlyRole(DEFAULT_ADMIN_ROLE) {
        mintMax[_status] = _max;
    }

    function setMintPerMax(Status _status, uint256 _max) public onlyRole(DEFAULT_ADMIN_ROLE) {
        mintPerMax[_status] = _max;
    }

    // Royalty
    function setDefaultRoyalty(address _receiver, uint96 _feeNumerator) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _setDefaultRoyalty(_receiver, _feeNumerator);
    }

    function deleteDefaultRoyalty() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _deleteDefaultRoyalty();
    }

    function setTokenRoyalty(
        uint256 _tokenId,
        address _receiver,
        uint96 _feeNumerator
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _setTokenRoyalty(_tokenId, _receiver, _feeNumerator);
    }

    function resetTokenRoyalty(uint256 _tokenId) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _resetTokenRoyalty(_tokenId);
    }

    // Tools
    function currentTime() private view returns (uint256) {
        return block.timestamp;
    }

    function withdraw() public onlyRole(DEFAULT_ADMIN_ROLE) {
        uint balance = address(this).balance;
        payable(msg.sender).transfer(balance);
    }

    function withdrawToken() public onlyRole(DEFAULT_ADMIN_ROLE) {
        IERC20 arb = IERC20(tokenContract);
        uint256 balance = arb.balanceOf(address(this));
        arb.transfer(msg.sender, balance);
    }

    function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize)
        internal
        whenNotPaused
        override(ERC721, ERC721Enumerable)
    {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    // The following functions are overrides required by Solidity.

    function _burn(uint256 tokenId) internal override(ERC721) {
        super._burn(tokenId);
        _resetTokenRoyalty(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC2981, ERC721Enumerable, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}