// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

interface IAgentId {
    function balanceOf(address account) external view returns (uint256);
}

interface ILintToken {
    function burnFrom(address account, uint256 amount) external;
}

/// @title Seolint Scan — SCAN, the daily Node NFT of Seolint
/// @notice One day = one plate. A day runs 12:00 UTC -> next 12:00 UTC (the
///         seal): dayId = (block.timestamp - 12 hours) / 1 days, and
///         dayStart(dayId) = dayId * 1 days + 12 hours.
///
///         Lanes (all bound by the 1,200 Scans/day global cap):
///         - Free: 1 per wallet per day, needs a Binance Agent ID (registry
///           balanceOf > 0, same check as TalvioBNB / VoltaGent). Global free
///           quota: 300 per absolute 6-hour bucket (00/06/12/18 UTC).
///         - Paid: scans priced by the wallet's count that day — the next
///           scan number 1-5 costs 0.0002 BNB, 6-10 costs 0.0004 BNB (scan
///           #1 is normally the free one). Max 10 per wallet per day across
///           the free + paid lanes. Overpayment refunded.
///         - Pass: a SeolintPass holder mints 1 extra Scan per day, no Agent
///           ID. Counted in the daily cap and in the wallet's day count.
///         - Burn: burn 50,000 LINT (approve this contract first; spent via
///           burnFrom) for 1 extra Scan beyond the 10/day wallet max.
///
///         Traits come from seed = keccak256(dayId, tokenId, minter):
///         Royal if seed % 1000 >= 970 (~3 in 100), kind = seed % 3
///         (0 Cotton, 1 Wool, 2 Silk). Claims are paid by the separate
///         LintClaim contracts; this contract only records the claimed flag
///         (markClaimed, restricted to registered claim contracts) and the
///         per-day unique participant counts the claim tiers are based on.
contract SeolintScan is ERC721, Ownable, ReentrancyGuard {
    using Strings for uint256;

    // ---------- locked numbers ----------
    uint256 public constant DAY_CAP = 1200;
    uint256 public constant MAX_PER_WALLET_DAY = 10;
    uint256 public constant FREE_PER_PHASE = 300;
    uint256 public constant PRICE_LOW = 0.0002 ether; // wallet's scans #1-5 that day
    uint256 public constant PRICE_HIGH = 0.0004 ether; // wallet's scans #6-10 that day
    uint256 public constant BURN_COST = 50_000 ether; // 50,000 LINT
    /// @notice Binance Agent ID registry on BNB Chain. Read-only check; the
    ///         registry itself is not owned or controlled by this contract.
    address public constant AGENT_ID_REGISTRY = 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F;

    // ---------- state ----------
    uint256 public totalMinted;
    bool public mintOpen;
    string private _baseTokenURI;

    ILintToken public lintToken;
    IERC721 public passContract;
    mapping(address => bool) public isClaimContract;

    struct ScanData {
        uint256 dayId;
        uint256 dayIndex; // this Scan's number within its day, from 1
        uint8 kind; // 0 Cotton, 1 Wool, 2 Silk
        bool royal;
        bool claimed;
    }
    mapping(uint256 => ScanData) private _scans;

    mapping(uint256 => uint256) public mintedInDay; // dayId => total Scans
    mapping(uint256 => mapping(address => uint256)) public walletDayCount;
    mapping(uint256 => mapping(address => bool)) public freeUsedInDay;
    mapping(uint256 => mapping(address => bool)) public passUsedInDay;
    mapping(uint256 => uint256) public freeInPhase; // absolute 6h bucket => free mints
    mapping(uint256 => uint256) public dayParticipants; // dayId => unique wallets
    mapping(uint256 => mapping(address => bool)) private _isParticipant;

    event MintOpenSet(bool open);
    event BaseURISet(string uri);
    event LintTokenSet(address token);
    event PassContractSet(address pass);
    event ClaimContractSet(address claim, bool allowed);
    event ScanMinted(
        address indexed minter,
        uint256 indexed tokenId,
        uint256 indexed dayId,
        uint256 dayIndex,
        uint8 kind,
        bool royal,
        uint8 lane // 0 free, 1 paid, 2 pass, 3 burn
    );
    event ScanClaimed(uint256 indexed tokenId, address indexed claimContract);

    constructor() ERC721("Seolint Scan", "SCAN") {}

    // ---------- day math ----------
    function currentDay() public view returns (uint256) {
        return (block.timestamp - 12 hours) / 1 days;
    }

    function dayStart(uint256 dayId) public pure returns (uint256) {
        return dayId * 1 days + 12 hours;
    }

    /// @notice Claims for a day open at its seal + 6 hours and never expire.
    function claimOpensAt(uint256 dayId) public pure returns (uint256) {
        return dayStart(dayId) + 1 days + 6 hours;
    }

    function currentPhase() public view returns (uint256) {
        return block.timestamp / 6 hours;
    }

    // ---------- views ----------
    function hasAgentId(address wallet) public view returns (bool) {
        return IAgentId(AGENT_ID_REGISTRY).balanceOf(wallet) > 0;
    }

    function scanInfo(uint256 tokenId)
        external
        view
        returns (uint256 dayId, uint256 dayIndex, uint8 kind, bool royal, bool claimed)
    {
        require(_exists(tokenId), "no token");
        ScanData storage s = _scans[tokenId];
        return (s.dayId, s.dayIndex, s.kind, s.royal, s.claimed);
    }

    /// @notice Price of the wallet's next paid Scan right now (0 once the
    ///         wallet is at the 10/day normal-lane max).
    function nextPaidPrice(address wallet) public view returns (uint256) {
        uint256 n = walletDayCount[currentDay()][wallet] + 1;
        if (n > MAX_PER_WALLET_DAY) return 0;
        return n <= 5 ? PRICE_LOW : PRICE_HIGH;
    }

    function freeRemainingInPhase() public view returns (uint256) {
        uint256 used = freeInPhase[currentPhase()];
        return used >= FREE_PER_PHASE ? 0 : FREE_PER_PHASE - used;
    }

    // ---------- mint lanes ----------
    function mintFree() external nonReentrant {
        require(mintOpen, "mint closed");
        uint256 dayId = currentDay();
        require(!freeUsedInDay[dayId][msg.sender], "free used today");
        require(walletDayCount[dayId][msg.sender] < MAX_PER_WALLET_DAY, "wallet day max");
        require(hasAgentId(msg.sender), "no Agent ID");
        uint256 phase = currentPhase();
        require(freeInPhase[phase] < FREE_PER_PHASE, "phase free quota full");
        freeUsedInDay[dayId][msg.sender] = true;
        freeInPhase[phase] += 1;
        _mintScan(msg.sender, dayId, 0);
    }

    function mintPaid() external payable nonReentrant {
        require(mintOpen, "mint closed");
        uint256 dayId = currentDay();
        uint256 count = walletDayCount[dayId][msg.sender];
        require(count < MAX_PER_WALLET_DAY, "wallet day max");
        uint256 price = (count + 1) <= 5 ? PRICE_LOW : PRICE_HIGH;
        require(msg.value >= price, "insufficient BNB");
        _mintScan(msg.sender, dayId, 1);
        if (msg.value > price) {
            (bool ok, ) = payable(msg.sender).call{value: msg.value - price}("");
            require(ok, "refund failed");
        }
    }

    function mintWithPass() external nonReentrant {
        require(mintOpen, "mint closed");
        require(address(passContract) != address(0), "pass not set");
        require(passContract.balanceOf(msg.sender) > 0, "no Pass");
        uint256 dayId = currentDay();
        require(!passUsedInDay[dayId][msg.sender], "pass used today");
        passUsedInDay[dayId][msg.sender] = true;
        _mintScan(msg.sender, dayId, 2);
    }

    function mintWithBurn() external nonReentrant {
        require(mintOpen, "mint closed");
        require(address(lintToken) != address(0), "token not set");
        // Spends the minter's LINT via burnFrom — the minter must have
        // approved this contract for at least 50,000 LINT first.
        lintToken.burnFrom(msg.sender, BURN_COST);
        _mintScan(msg.sender, currentDay(), 3);
    }

    // ---------- claims ----------
    /// @notice Only a registered LintClaim contract may mark a Scan claimed.
    function markClaimed(uint256 tokenId) external {
        require(isClaimContract[msg.sender], "not a claim contract");
        require(_exists(tokenId), "no token");
        require(!_scans[tokenId].claimed, "already claimed");
        _scans[tokenId].claimed = true;
        emit ScanClaimed(tokenId, msg.sender);
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

    function setLintToken(address token) external onlyOwner {
        lintToken = ILintToken(token);
        emit LintTokenSet(token);
    }

    function setPassContract(address pass) external onlyOwner {
        passContract = IERC721(pass);
        emit PassContractSet(pass);
    }

    function setClaimContract(address claim, bool allowed) external onlyOwner {
        isClaimContract[claim] = allowed;
        emit ClaimContractSet(claim, allowed);
    }

    function setClaimContracts(address[] calldata claims, bool allowed) external onlyOwner {
        for (uint256 i = 0; i < claims.length; i++) {
            isClaimContract[claims[i]] = allowed;
            emit ClaimContractSet(claims[i], allowed);
        }
    }

    function withdraw() external onlyOwner {
        uint256 bal = address(this).balance;
        require(bal > 0, "empty");
        (bool ok, ) = payable(owner()).call{value: bal}("");
        require(ok, "withdraw failed");
    }

    // ---------- internals ----------
    function _mintScan(address minter, uint256 dayId, uint8 lane) internal {
        require(mintedInDay[dayId] < DAY_CAP, "day cap full");
        totalMinted += 1;
        uint256 tokenId = totalMinted;
        mintedInDay[dayId] += 1;
        walletDayCount[dayId][minter] += 1;
        if (!_isParticipant[dayId][minter]) {
            _isParticipant[dayId][minter] = true;
            dayParticipants[dayId] += 1;
        }
        uint256 seed = uint256(keccak256(abi.encode(dayId, tokenId, minter)));
        ScanData storage s = _scans[tokenId];
        s.dayId = dayId;
        s.dayIndex = mintedInDay[dayId];
        s.kind = uint8(seed % 3);
        s.royal = (seed % 1000) >= 970;
        _safeMint(minter, tokenId);
        emit ScanMinted(minter, tokenId, dayId, s.dayIndex, s.kind, s.royal, lane);
    }

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
