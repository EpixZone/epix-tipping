// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IEpixTipping
/// @notice Interface for the EpixTipping contract.
///         Enables tipping content creators on EpixNet sites with native EPIX.
interface IEpixTipping {
    // -----------------------------------------------------------------------
    // Structs
    // -----------------------------------------------------------------------

    /// @notice A top tipper entry (address + cumulative amount + xID name).
    struct TopTipper {
        address tipper;
        uint96 amount;
        string xidName;
    }

    /// @notice A recent tip entry (address + single-tip amount + timestamp + xID name).
    struct RecentTip {
        address tipper;
        uint256 amount;
        uint64 timestamp;
        string xidName;
    }

    /// @notice Full stats for a content hash, returned by getContentInfo().
    struct ContentInfo {
        address creator;
        uint256 totalAmount;
        uint32 uniqueTippers;
        uint8 topCount;
        uint8 recentCount;
        TopTipper[3] top3;
        RecentTip[3] last3;
    }

    // -----------------------------------------------------------------------
    // Events
    // -----------------------------------------------------------------------

    /// @notice Emitted when a tip is sent.
    event Tipped(bytes32 indexed contentHash, address indexed tipper, address indexed recipient, uint256 amount);

    /// @notice Emitted when a content hash is first tipped (creator bound).
    event ContentRegistered(bytes32 indexed contentHash, address indexed creator);

    // -----------------------------------------------------------------------
    // Write functions
    // -----------------------------------------------------------------------

    /// @notice Tip a content creator by direct address.
    ///         On first tip to a contentHash, the recipient is permanently bound.
    ///         On subsequent tips, pass the same recipient or address(0) to use the stored creator.
    /// @param contentHash The content hash identifying the content
    /// @param recipient The content creator's address
    function tip(bytes32 contentHash, address recipient) external payable;

    /// @notice Tip a content creator by resolving their xID name via the precompile.
    /// @param contentHash The content hash identifying the content
    /// @param name The xID name (e.g., "mud")
    /// @param tld The xID TLD (e.g., "epix")
    function tipByXid(bytes32 contentHash, string calldata name, string calldata tld) external payable;

    /// @notice Refresh the caller's cached xID name.
    ///         Call this if your xID name has changed since your first tip.
    function refreshXidName() external;

    // -----------------------------------------------------------------------
    // Read functions
    // -----------------------------------------------------------------------

    /// @notice Get all stats for a content hash in one call (for the tip modal).
    /// @param contentHash The content hash to query
    /// @return info The full content stats
    function getContentInfo(bytes32 contentHash) external view returns (ContentInfo memory info);

    /// @notice Get summary stats for a content hash (for the tip button badge).
    /// @param contentHash The content hash to query
    /// @return creator The content creator address
    /// @return totalAmount Total EPIX tipped
    /// @return uniqueTippers Number of unique tippers
    function getContentSummary(bytes32 contentHash)
        external
        view
        returns (address creator, uint256 totalAmount, uint32 uniqueTippers);

    /// @notice Batch-get summaries for multiple content hashes in one call.
    ///         Returns parallel arrays — index i corresponds to contentHashes[i].
    ///         Ideal for loading tip badges on a page with many posts (1 RPC call instead of N).
    /// @param contentHashes Array of content hashes to query
    /// @return creators Array of creator addresses
    /// @return totalAmounts Array of total EPIX tipped
    /// @return uniqueTipperCounts Array of unique tipper counts
    function getContentSummaryBatch(bytes32[] calldata contentHashes)
        external
        view
        returns (address[] memory creators, uint256[] memory totalAmounts, uint32[] memory uniqueTipperCounts);

    /// @notice Get just the unique tipper count for a single content hash.
    /// @param contentHash The content hash to query
    /// @return count Number of unique tippers
    function getTipperCount(bytes32 contentHash) external view returns (uint32 count);

    /// @notice Batch-get tipper counts for multiple content hashes in one call.
    ///         Minimal data for rendering tip badge icons on page load (1 slot read per hash).
    /// @param contentHashes Array of content hashes to query
    /// @return counts Array of unique tipper counts (index i = contentHashes[i])
    function getTipperCountBatch(bytes32[] calldata contentHashes) external view returns (uint32[] memory counts);

    /// @notice Get the cumulative amount a specific tipper has sent to a content hash.
    /// @param contentHash The content hash
    /// @param tipper The tipper's address
    /// @return amount The cumulative amount
    function getTipperAmount(bytes32 contentHash, address tipper) external view returns (uint256 amount);

    /// @notice Compute a content hash from its components (convenience/verification).
    /// @param siteAddress The site's cosmos address string
    /// @param authorDirectory The author's xID directory string
    /// @param postId The post identifier string
    /// @return contentHash The computed keccak256 hash
    function computeContentHash(string calldata siteAddress, string calldata authorDirectory, string calldata postId)
        external
        pure
        returns (bytes32 contentHash);
}
