// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/// @title Seolint Pass — SPASS
/// @notice The second Seolint NFT: a transferable entry pass. Anyone can buy
///         one with a normal wallet — no Binance Agent ID, no quiz. Fixed
///         price 0.00123 BNB, unlimited supply, never expires. Holding a Pass
///         lets a wallet mint 1 extra Scan per day through the Pass lane of
///         SeolintScan. Token IDs are sequential from 1.
contract SeolintPass is ERC721, Ownable, ReentrancyGuard {
    using Strings for uint256;

    uint256 public constant PRICE = 0.00123 ether;

    uint256 public totalMinted;
    bool public mintOpen;
    string private _baseTokenURI;

    event MintOpenSet(bool open);
    event BaseURISet(string uri);
    event PassMinted(address indexed buyer, uint256 firstId, uint256 qty);

    constructor() ERC721("Seolint Pass", "SPASS") {}

    // ---------- mint ----------
    function mint(uint256 qty) external payable nonReentrant {
        require(mintOpen, "mint closed");
        require(qty >= 1 && qty <= 10, "bad qty");
        uint256 cost = PRICE * qty;
        require(msg.value >= cost, "insufficient BNB");

        uint256 firstId = totalMinted + 1;
        for (uint256 i = 0; i < qty; i++) {
            totalMinted += 1;
            _safeMint(msg.sender, totalMinted);
        }
        emit PassMinted(msg.sender, firstId, qty);

        if (msg.value > cost) {
            (bool ok, ) = payable(msg.sender).call{value: msg.value - cost}("");
            require(ok, "refund failed");
        }
    }

    // ---------- owner ----------
    function setMintOpen(bool open_) external onlyOwner {
        mintOpen = open_;
        emit MintOpenSet(open_);
    }

    function setBaseURI(string calldata uri) external onlyOwner {
        _baseTokenURI = uri;
        emit BaseURISet(uri);
    }

    function withdraw() external onlyOwner {
        uint256 bal = address(this).balance;
        require(bal > 0, "empty");
        (bool ok, ) = payable(owner()).call{value: bal}("");
        require(ok, "withdraw failed");
    }

    // ---------- views ----------
    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "no token");
        string memory base = _baseURI();
        return bytes(base).length > 0
            ? string(abi.encodePacked(base, tokenId.toString(), ".json"))
            : "";
    }
}
