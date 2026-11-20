// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface ISeolintScan {
    function ownerOf(uint256 tokenId) external view returns (address);
    function scanInfo(uint256 tokenId)
        external
        view
        returns (uint256 dayId, uint256 dayIndex, uint8 kind, bool royal, bool claimed);
    function dayParticipants(uint256 dayId) external view returns (uint256);
    function claimOpensAt(uint256 dayId) external view returns (uint256);
    function markClaimed(uint256 tokenId) external;
}

/// @title LintClaim — one of the three identical $LINT claim contracts
/// @notice Deploy three copies of this contract. The owner funds each with
///         2,000,000,000 LINT (pool total 6,000,000,000 = 60% of supply),
///         points each at the SeolintScan contract, and registers all three
///         on the Scan contract. A Scan NFT can be claimed exactly once
///         across all three: the claimed flag lives in the Scan contract.
///
///         Amount, by the claim day's unique participant count recorded in
///         the Scan contract: <25 -> 2,500 LINT · 25-100 -> 12,500 LINT ·
///         >100 -> 60,000 LINT · a Royal Scan pays 250,000 LINT regardless.
///         Claims open at the day's seal + 6 hours and never expire.
///         Claim fee in BNB: 0.000277 standard, 0.000555 Royal; overpayment
///         refunded; fees accumulate here for the owner to withdraw.
contract LintClaim is Ownable, ReentrancyGuard {
    uint256 public constant TIER_LOW = 2_500 ether;
    uint256 public constant TIER_MID = 12_500 ether;
    uint256 public constant TIER_HIGH = 60_000 ether;
    uint256 public constant ROYAL_AMOUNT = 250_000 ether;
    uint256 public constant FEE = 0.000277 ether;
    uint256 public constant FEE_ROYAL = 0.000555 ether;

    IERC20 public immutable lintToken;
    ISeolintScan public scanContract;

    event ScanContractSet(address scan);
    event Claimed(address indexed holder, uint256 indexed tokenId, uint256 amount, uint256 fee);

    constructor(address lintToken_) {
        require(lintToken_ != address(0), "zero token");
        lintToken = IERC20(lintToken_);
    }

    function setScanContract(address scan) external onlyOwner {
        require(scan != address(0), "zero scan");
        scanContract = ISeolintScan(scan);
        emit ScanContractSet(scan);
    }

    /// @notice What `tokenId` would pay right now, and its claim fee.
    /// @return amount LINT amount (0 once claimed)
    /// @return fee BNB fee due with the claim
    /// @return open true once the claim window has opened
    function preview(uint256 tokenId) external view returns (uint256 amount, uint256 fee, bool open) {
        require(address(scanContract) != address(0), "scan not set");
        (uint256 dayId, , , bool royal, bool claimed) = scanContract.scanInfo(tokenId);
        if (claimed) return (0, 0, false);
        fee = royal ? FEE_ROYAL : FEE;
        open = block.timestamp >= scanContract.claimOpensAt(dayId);
        if (royal) return (ROYAL_AMOUNT, fee, open);
        uint256 p = scanContract.dayParticipants(dayId);
        amount = p < 25 ? TIER_LOW : (p <= 100 ? TIER_MID : TIER_HIGH);
        return (amount, fee, open);
    }

    function claim(uint256 tokenId) external payable nonReentrant {
        require(address(scanContract) != address(0), "scan not set");
        require(scanContract.ownerOf(tokenId) == msg.sender, "not your Scan");
        (uint256 dayId, , , bool royal, bool claimed) = scanContract.scanInfo(tokenId);
        require(!claimed, "already claimed");
        require(block.timestamp >= scanContract.claimOpensAt(dayId), "claims not open yet");

        uint256 fee = royal ? FEE_ROYAL : FEE;
        require(msg.value >= fee, "fee too low");

        uint256 amount;
        if (royal) {
            amount = ROYAL_AMOUNT;
        } else {
            uint256 p = scanContract.dayParticipants(dayId);
            amount = p < 25 ? TIER_LOW : (p <= 100 ? TIER_MID : TIER_HIGH);
        }

        // Mark first (the flag lives in the Scan contract, so the other two
        // claim contracts can never pay this NFT again), then pay out.
        scanContract.markClaimed(tokenId);
        require(lintToken.transfer(msg.sender, amount), "LINT transfer failed");
        emit Claimed(msg.sender, tokenId, amount, fee);

        if (msg.value > fee) {
            (bool ok, ) = payable(msg.sender).call{value: msg.value - fee}("");
            require(ok, "refund failed");
        }
    }

    // ---------- owner ----------
    /// @notice Withdraw the collected BNB claim fees.
    function withdraw() external onlyOwner {
        uint256 bal = address(this).balance;
        require(bal > 0, "empty");
        (bool ok, ) = payable(owner()).call{value: bal}("");
        require(ok, "withdraw failed");
    }

    /// @notice Recover LINT held by this contract (e.g. an overfunded pool).
    function withdrawLint(uint256 amount) external onlyOwner {
        require(lintToken.transfer(owner(), amount), "LINT transfer failed");
    }
}
