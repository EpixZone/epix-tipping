// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IEpixTipping} from "./IEpixTipping.sol";
import {XID} from "./IXID.sol";

/// @title EpixTipping
/// @notice Tipping contract for EpixNet sites. Users can tip content creators
///         with native EPIX. Tracks top 3 tippers, last 3 tips, and totals
///         per content hash for efficient UI rendering.
contract EpixTipping is IEpixTipping {
    // -----------------------------------------------------------------------
    // Constants
    // -----------------------------------------------------------------------

    /// @dev Maximum entries in top tippers leaderboard.
    uint8 private constant _TOP_SIZE = 3;

    /// @dev Maximum entries in recent tips circular buffer.
    uint8 private constant _RECENT_SIZE = 3;

    // -----------------------------------------------------------------------
    // Storage types
    // -----------------------------------------------------------------------

    struct TipperEntry {
        address tipper; // 20 bytes
        uint96 amount; //  12 bytes - cumulative, packed in 1 slot
    }

    struct RecentEntry {
        address tipper; //   20 bytes |
        uint64 timestamp; //  8 bytes | slot N
        uint256 amount; //              slot N+1
    }

    struct Stats {
        address creator; //       20 bytes |
        uint32 uniqueTippers; //   4 bytes |
        uint8 topCount; //         1 byte  | slot 0
        uint8 recentIndex; //      1 byte  |
        uint8 recentCount; //      1 byte  |
        uint256 totalAmount; //             slot 1
        TipperEntry[3] top3; //             slots 2-4
        RecentEntry[3] last3; //            slots 5-10
    }

    // -----------------------------------------------------------------------
    // Storage
    // -----------------------------------------------------------------------

    /// @dev Reentrancy lock.
    bool private _locked;

    /// @dev contentHash => Stats
    mapping(bytes32 => Stats) private _stats;

    /// @dev contentHash => tipper => cumulative amount
    mapping(bytes32 => mapping(address => uint256)) private _tipperAmounts;

    /// @dev tipper address => cached xID name (e.g. "mud.epix"), resolved once
    mapping(address => string) private _tipperXidNames;

    // -----------------------------------------------------------------------
    // Modifiers
    // -----------------------------------------------------------------------

    modifier nonReentrant() {
        require(!_locked, "Reentrant call");
        _locked = true;
        _;
        _locked = false;
    }

    // -----------------------------------------------------------------------
    // External functions
    // -----------------------------------------------------------------------

    /// @inheritdoc IEpixTipping
    function tip(bytes32 contentHash, address recipient) external payable {
        _tip(contentHash, recipient);
    }

    /// @inheritdoc IEpixTipping
    function tipByXid(bytes32 contentHash, string calldata name, string calldata tld) external payable {
        address resolved = _tryResolve(name, tld);
        require(resolved != address(0), "xID: name not found");
        _tip(contentHash, resolved);
    }

    /// @inheritdoc IEpixTipping
    function refreshXidName() external {
        (string memory name, string memory tld) = _tryReverseResolve(msg.sender);
        if (bytes(name).length > 0) {
            _tipperXidNames[msg.sender] = string.concat(name, ".", tld);
        } else {
            delete _tipperXidNames[msg.sender];
        }
    }

    /// @inheritdoc IEpixTipping
    function getContentInfo(bytes32 contentHash) external view returns (ContentInfo memory info) {
        Stats storage s = _stats[contentHash];
        info.creator = s.creator;
        info.totalAmount = s.totalAmount;
        info.uniqueTippers = s.uniqueTippers;
        info.topCount = s.topCount;
        info.recentCount = s.recentCount;

        for (uint8 i = 0; i < s.topCount; i++) {
            info.top3[i] = TopTipper(s.top3[i].tipper, s.top3[i].amount, _tipperXidNames[s.top3[i].tipper]);
        }

        // Return last3 in reverse chronological order (most recent first)
        for (uint8 i = 0; i < s.recentCount; i++) {
            uint8 idx = uint8((uint256(s.recentIndex) + _RECENT_SIZE - 1 - i) % _RECENT_SIZE);
            info.last3[i] = RecentTip(
                s.last3[idx].tipper, s.last3[idx].amount, s.last3[idx].timestamp, _tipperXidNames[s.last3[idx].tipper]
            );
        }
    }

    /// @inheritdoc IEpixTipping
    function getContentSummary(bytes32 contentHash)
        external
        view
        returns (address creator, uint256 totalAmount, uint32 uniqueTippers)
    {
        Stats storage s = _stats[contentHash];
        return (s.creator, s.totalAmount, s.uniqueTippers);
    }

    /// @inheritdoc IEpixTipping
    function getContentSummaryBatch(bytes32[] calldata contentHashes)
        external
        view
        returns (address[] memory creators, uint256[] memory totalAmounts, uint32[] memory uniqueTipperCounts)
    {
        uint256 len = contentHashes.length;
        creators = new address[](len);
        totalAmounts = new uint256[](len);
        uniqueTipperCounts = new uint32[](len);

        for (uint256 i = 0; i < len; i++) {
            Stats storage s = _stats[contentHashes[i]];
            creators[i] = s.creator;
            totalAmounts[i] = s.totalAmount;
            uniqueTipperCounts[i] = s.uniqueTippers;
        }
    }

    /// @inheritdoc IEpixTipping
    function getTipperCount(bytes32 contentHash) external view returns (uint32) {
        return _stats[contentHash].uniqueTippers;
    }

    /// @inheritdoc IEpixTipping
    function getTipperCountBatch(bytes32[] calldata contentHashes) external view returns (uint32[] memory counts) {
        uint256 len = contentHashes.length;
        counts = new uint32[](len);
        for (uint256 i = 0; i < len; i++) {
            counts[i] = _stats[contentHashes[i]].uniqueTippers;
        }
    }

    /// @inheritdoc IEpixTipping
    function getTipperAmount(bytes32 contentHash, address tipper) external view returns (uint256) {
        return _tipperAmounts[contentHash][tipper];
    }

    /// @inheritdoc IEpixTipping
    function computeContentHash(string calldata siteAddress, string calldata authorDirectory, string calldata postId)
        external
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(siteAddress, authorDirectory, postId));
    }

    // -----------------------------------------------------------------------
    // Internal
    // -----------------------------------------------------------------------

    function _tip(bytes32 contentHash, address recipient) internal nonReentrant {
        require(msg.value > 0, "Tip must be > 0");

        Stats storage s = _stats[contentHash];

        // Register creator on first tip, or validate on subsequent tips
        if (s.creator == address(0)) {
            require(recipient != address(0), "Recipient required on first tip");
            s.creator = recipient;
            emit ContentRegistered(contentHash, recipient);
        } else {
            if (recipient != address(0)) {
                require(recipient == s.creator, "Recipient mismatch");
            }
            recipient = s.creator;
        }

        // Update totals
        s.totalAmount += msg.value;

        // Update per-tipper cumulative and unique count
        uint256 prevAmount = _tipperAmounts[contentHash][msg.sender];
        uint256 newAmount = prevAmount + msg.value;
        _tipperAmounts[contentHash][msg.sender] = newAmount;

        if (prevAmount == 0) {
            s.uniqueTippers++;
            // Cache tipper's xID name on first tip (F-04: wrapped in try/catch)
            if (bytes(_tipperXidNames[msg.sender]).length == 0) {
                (string memory name, string memory tld) = _tryReverseResolve(msg.sender);
                if (bytes(name).length > 0) {
                    _tipperXidNames[msg.sender] = string.concat(name, ".", tld);
                }
            }
        }

        // Update top 3
        uint96 newAmount96 = _safeToUint96(newAmount);
        _updateTop3(s, msg.sender, newAmount96);

        // Update last 3 circular buffer
        _updateLast3(s, msg.sender, msg.value, uint64(block.timestamp));

        // Transfer EPIX to creator (checks-effects-interactions)
        (bool success,) = payable(recipient).call{value: msg.value}("");
        require(success, "Transfer failed");

        emit Tipped(contentHash, msg.sender, recipient, msg.value);
    }

    function _updateTop3(Stats storage s, address tipper, uint96 newAmount) internal {
        // Check if already in top3
        for (uint8 i = 0; i < s.topCount; i++) {
            if (s.top3[i].tipper == tipper) {
                s.top3[i].amount = newAmount;
                // Bubble up if amount increased
                while (i > 0 && s.top3[i].amount > s.top3[i - 1].amount) {
                    TipperEntry memory tmp = s.top3[i - 1];
                    s.top3[i - 1] = s.top3[i];
                    s.top3[i] = tmp;
                    i--;
                }
                return;
            }
        }

        // Not in top3 - check if there is room or if it displaces #3
        if (s.topCount < _TOP_SIZE) {
            s.top3[s.topCount] = TipperEntry(tipper, newAmount);
            s.topCount++;
            // Bubble up
            uint8 i = s.topCount - 1;
            while (i > 0 && s.top3[i].amount > s.top3[i - 1].amount) {
                TipperEntry memory tmp = s.top3[i - 1];
                s.top3[i - 1] = s.top3[i];
                s.top3[i] = tmp;
                i--;
            }
        } else if (newAmount > s.top3[2].amount) {
            // Displace the #3 entry
            s.top3[2] = TipperEntry(tipper, newAmount);
            if (s.top3[2].amount > s.top3[1].amount) {
                TipperEntry memory tmp = s.top3[1];
                s.top3[1] = s.top3[2];
                s.top3[2] = tmp;
                if (s.top3[1].amount > s.top3[0].amount) {
                    tmp = s.top3[0];
                    s.top3[0] = s.top3[1];
                    s.top3[1] = tmp;
                }
            }
        }
    }

    function _updateLast3(Stats storage s, address tipper, uint256 amount, uint64 ts) internal {
        uint8 idx = s.recentIndex;
        s.last3[idx].tipper = tipper;
        s.last3[idx].timestamp = ts;
        s.last3[idx].amount = amount;
        s.recentIndex = uint8((uint256(idx) + 1) % _RECENT_SIZE);
        if (s.recentCount < _RECENT_SIZE) {
            s.recentCount++;
        }
    }

    function _safeToUint96(uint256 value) internal pure returns (uint96) {
        require(value <= type(uint96).max, "Amount overflow uint96");
        return uint96(value);
    }

    /// @dev Try to resolve an xID name. Returns address(0) if the precompile reverts.
    function _tryResolve(string calldata name, string calldata tld) private view returns (address) {
        try XID.resolve(name, tld) returns (address owner) {
            return owner;
        } catch {
            return address(0);
        }
    }

    /// @dev Try to reverse-resolve an address via the xID precompile.
    ///      Returns empty strings if the precompile reverts or is unavailable.
    function _tryReverseResolve(address addr) private view returns (string memory name, string memory tld) {
        try XID.reverseResolve(addr) returns (string memory n, string memory t) {
            return (n, t);
        } catch {
            return ("", "");
        }
    }
}
