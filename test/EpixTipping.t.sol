// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {EpixTipping} from "../src/EpixTipping.sol";
import {IEpixTipping} from "../src/IEpixTipping.sol";
import {XID_PRECOMPILE_ADDRESS} from "../src/IXID.sol";
import {MockXID} from "./mocks/MockXID.sol";

contract EpixTippingTest is Test {
    EpixTipping public tipping;
    MockXID public mockXid;

    address public creator = makeAddr("creator");
    address public tipper1 = makeAddr("tipper1");
    address public tipper2 = makeAddr("tipper2");
    address public tipper3 = makeAddr("tipper3");
    address public tipper4 = makeAddr("tipper4");

    bytes32 public contentHash1;

    function setUp() public {
        // Deploy mock xID and etch its code to the precompile address
        mockXid = new MockXID();
        vm.etch(XID_PRECOMPILE_ADDRESS, address(mockXid).code);

        // Configure mock: "mud.epix" -> creator
        MockXID(XID_PRECOMPILE_ADDRESS).setResolution("mud", "epix", creator);
        // Configure reverse resolution for tippers
        MockXID(XID_PRECOMPILE_ADDRESS).setResolution("alice", "epix", tipper1);
        MockXID(XID_PRECOMPILE_ADDRESS).setResolution("bob", "epix", tipper2);
        MockXID(XID_PRECOMPILE_ADDRESS).setResolution("charlie", "epix", tipper3);
        // tipper4 intentionally has no xID

        // Deploy tipping contract
        tipping = new EpixTipping();

        // Compute a test content hash
        contentHash1 = keccak256(abi.encode("epix1talk58lw26c0cyrtuu8axptne2p6zf33s7xxwu", "mud.epix", "42"));

        // Fund tippers
        vm.deal(tipper1, 100 ether);
        vm.deal(tipper2, 100 ether);
        vm.deal(tipper3, 100 ether);
        vm.deal(tipper4, 100 ether);
    }

    // -----------------------------------------------------------------------
    // tip() — basic
    // -----------------------------------------------------------------------

    function test_tip_firstTip_registersCreator() public {
        uint256 creatorBefore = creator.balance;

        vm.expectEmit(true, true, false, false);
        emit IEpixTipping.ContentRegistered(contentHash1, creator);

        vm.expectEmit(true, true, true, true);
        emit IEpixTipping.Tipped(contentHash1, tipper1, creator, 1 ether);

        vm.prank(tipper1);
        tipping.tip{value: 1 ether}(contentHash1, creator);

        assertEq(creator.balance - creatorBefore, 1 ether, "Creator should receive tip");
    }

    function test_tip_subsequentTip_sameCreator() public {
        // First tip
        vm.prank(tipper1);
        tipping.tip{value: 1 ether}(contentHash1, creator);

        // Second tip with same creator
        uint256 creatorBefore = creator.balance;
        vm.prank(tipper2);
        tipping.tip{value: 2 ether}(contentHash1, creator);

        assertEq(creator.balance - creatorBefore, 2 ether);
    }

    function test_tip_subsequentTip_zeroRecipient() public {
        // First tip registers creator
        vm.prank(tipper1);
        tipping.tip{value: 1 ether}(contentHash1, creator);

        // Second tip with address(0) uses stored creator
        uint256 creatorBefore = creator.balance;
        vm.prank(tipper2);
        tipping.tip{value: 2 ether}(contentHash1, address(0));

        assertEq(creator.balance - creatorBefore, 2 ether);
    }

    function test_tip_transfersFullAmount() public {
        uint256 creatorBefore = creator.balance;
        uint256 tipAmount = 3.5 ether;

        vm.prank(tipper1);
        tipping.tip{value: tipAmount}(contentHash1, creator);

        assertEq(creator.balance - creatorBefore, tipAmount, "Full amount should be transferred");
    }

    // -----------------------------------------------------------------------
    // tip() — reverts
    // -----------------------------------------------------------------------

    function test_tip_revert_zeroValue() public {
        vm.prank(tipper1);
        vm.expectRevert("Tip must be > 0");
        tipping.tip{value: 0}(contentHash1, creator);
    }

    function test_tip_revert_zeroRecipientOnFirstTip() public {
        vm.prank(tipper1);
        vm.expectRevert("Recipient required on first tip");
        tipping.tip{value: 1 ether}(contentHash1, address(0));
    }

    function test_tip_revert_wrongRecipient() public {
        // First tip
        vm.prank(tipper1);
        tipping.tip{value: 1 ether}(contentHash1, creator);

        // Second tip with wrong recipient
        vm.prank(tipper2);
        vm.expectRevert("Recipient mismatch");
        tipping.tip{value: 1 ether}(contentHash1, tipper3);
    }

    // -----------------------------------------------------------------------
    // tipByXid()
    // -----------------------------------------------------------------------

    function test_tipByXid_resolvesAndTips() public {
        uint256 creatorBefore = creator.balance;

        vm.prank(tipper1);
        tipping.tipByXid{value: 1 ether}(contentHash1, "mud", "epix");

        assertEq(creator.balance - creatorBefore, 1 ether);

        // Creator should be registered
        (address storedCreator,,) = tipping.getContentSummary(contentHash1);
        assertEq(storedCreator, creator);
    }

    function test_tipByXid_revert_unregisteredName() public {
        vm.prank(tipper1);
        vm.expectRevert("xID: name not found");
        tipping.tipByXid{value: 1 ether}(contentHash1, "unknown", "epix");
    }

    // -----------------------------------------------------------------------
    // Unique tipper counting
    // -----------------------------------------------------------------------

    function test_uniqueTippers_countCorrect() public {
        // tipper1 tips twice
        vm.prank(tipper1);
        tipping.tip{value: 1 ether}(contentHash1, creator);
        vm.prank(tipper1);
        tipping.tip{value: 1 ether}(contentHash1, creator);

        // tipper2 tips once
        vm.prank(tipper2);
        tipping.tip{value: 1 ether}(contentHash1, creator);

        (,, uint32 uniqueTippers) = tipping.getContentSummary(contentHash1);
        assertEq(uniqueTippers, 2);
    }

    // -----------------------------------------------------------------------
    // Total amount
    // -----------------------------------------------------------------------

    function test_multipleTips_totalAmountAccumulates() public {
        vm.prank(tipper1);
        tipping.tip{value: 1 ether}(contentHash1, creator);

        vm.prank(tipper2);
        tipping.tip{value: 2 ether}(contentHash1, creator);

        vm.prank(tipper1);
        tipping.tip{value: 0.5 ether}(contentHash1, creator);

        (, uint256 totalAmount,) = tipping.getContentSummary(contentHash1);
        assertEq(totalAmount, 3.5 ether);
    }

    // -----------------------------------------------------------------------
    // Top 3 tracking
    // -----------------------------------------------------------------------

    function test_top3_singleTipper() public {
        vm.prank(tipper1);
        tipping.tip{value: 5 ether}(contentHash1, creator);

        IEpixTipping.ContentInfo memory info = tipping.getContentInfo(contentHash1);
        assertEq(info.topCount, 1);
        assertEq(info.top3[0].tipper, tipper1);
        assertEq(info.top3[0].amount, 5 ether);
        assertEq(info.top3[0].xidName, "alice.epix");
    }

    function test_top3_threeTippers_correctOrder() public {
        vm.prank(tipper1);
        tipping.tip{value: 1 ether}(contentHash1, creator);

        vm.prank(tipper2);
        tipping.tip{value: 3 ether}(contentHash1, creator);

        vm.prank(tipper3);
        tipping.tip{value: 2 ether}(contentHash1, creator);

        IEpixTipping.ContentInfo memory info = tipping.getContentInfo(contentHash1);
        assertEq(info.topCount, 3);
        // Descending order: tipper2 (3), tipper3 (2), tipper1 (1)
        assertEq(info.top3[0].tipper, tipper2);
        assertEq(info.top3[0].amount, 3 ether);
        assertEq(info.top3[0].xidName, "bob.epix");
        assertEq(info.top3[1].tipper, tipper3);
        assertEq(info.top3[1].amount, 2 ether);
        assertEq(info.top3[1].xidName, "charlie.epix");
        assertEq(info.top3[2].tipper, tipper1);
        assertEq(info.top3[2].amount, 1 ether);
        assertEq(info.top3[2].xidName, "alice.epix");
    }

    function test_top3_displacement() public {
        // 3 tippers fill the top3
        vm.prank(tipper1);
        tipping.tip{value: 1 ether}(contentHash1, creator);
        vm.prank(tipper2);
        tipping.tip{value: 2 ether}(contentHash1, creator);
        vm.prank(tipper3);
        tipping.tip{value: 3 ether}(contentHash1, creator);

        // tipper4 (no xID) displaces tipper1 (currently #3 with 1 ether)
        vm.prank(tipper4);
        tipping.tip{value: 1.5 ether}(contentHash1, creator);

        IEpixTipping.ContentInfo memory info = tipping.getContentInfo(contentHash1);
        assertEq(info.topCount, 3);
        // tipper3 (3), tipper2 (2), tipper4 (1.5) — tipper1 displaced
        assertEq(info.top3[0].tipper, tipper3);
        assertEq(info.top3[0].xidName, "charlie.epix");
        assertEq(info.top3[1].tipper, tipper2);
        assertEq(info.top3[1].xidName, "bob.epix");
        assertEq(info.top3[2].tipper, tipper4);
        assertEq(info.top3[2].amount, 1.5 ether);
        // tipper4 has no xID — empty string
        assertEq(info.top3[2].xidName, "");
    }

    function test_top3_existingTipperRises() public {
        // tipper1=1, tipper2=5, tipper3=3 → order: tipper2, tipper3, tipper1
        vm.prank(tipper1);
        tipping.tip{value: 1 ether}(contentHash1, creator);
        vm.prank(tipper2);
        tipping.tip{value: 5 ether}(contentHash1, creator);
        vm.prank(tipper3);
        tipping.tip{value: 3 ether}(contentHash1, creator);

        // tipper1 tips 10 more → cumulative 11, should rise to #1
        vm.prank(tipper1);
        tipping.tip{value: 10 ether}(contentHash1, creator);

        IEpixTipping.ContentInfo memory info = tipping.getContentInfo(contentHash1);
        // New order: tipper1 (11), tipper2 (5), tipper3 (3)
        assertEq(info.top3[0].tipper, tipper1);
        assertEq(info.top3[0].amount, 11 ether);
        assertEq(info.top3[1].tipper, tipper2);
        assertEq(info.top3[1].amount, 5 ether);
        assertEq(info.top3[2].tipper, tipper3);
        assertEq(info.top3[2].amount, 3 ether);
    }

    // -----------------------------------------------------------------------
    // Last 3 tracking
    // -----------------------------------------------------------------------

    function test_last3_circularBuffer() public {
        // 5 tips — last3 should contain tips 3, 4, 5 in reverse chronological order
        vm.warp(100);
        vm.prank(tipper1);
        tipping.tip{value: 1 ether}(contentHash1, creator); // tip 1

        vm.warp(200);
        vm.prank(tipper2);
        tipping.tip{value: 2 ether}(contentHash1, creator); // tip 2

        vm.warp(300);
        vm.prank(tipper3);
        tipping.tip{value: 3 ether}(contentHash1, creator); // tip 3

        vm.warp(400);
        vm.prank(tipper1);
        tipping.tip{value: 4 ether}(contentHash1, creator); // tip 4

        vm.warp(500);
        vm.prank(tipper4);
        tipping.tip{value: 5 ether}(contentHash1, creator); // tip 5

        IEpixTipping.ContentInfo memory info = tipping.getContentInfo(contentHash1);
        assertEq(info.recentCount, 3);

        // Most recent first
        assertEq(info.last3[0].tipper, tipper4);
        assertEq(info.last3[0].amount, 5 ether);
        assertEq(info.last3[0].timestamp, 500);
        assertEq(info.last3[0].xidName, ""); // tipper4 has no xID

        assertEq(info.last3[1].tipper, tipper1);
        assertEq(info.last3[1].amount, 4 ether);
        assertEq(info.last3[1].timestamp, 400);
        assertEq(info.last3[1].xidName, "alice.epix");

        assertEq(info.last3[2].tipper, tipper3);
        assertEq(info.last3[2].amount, 3 ether);
        assertEq(info.last3[2].timestamp, 300);
        assertEq(info.last3[2].xidName, "charlie.epix");
    }

    function test_last3_lessThanThree() public {
        vm.warp(100);
        vm.prank(tipper1);
        tipping.tip{value: 1 ether}(contentHash1, creator);

        vm.warp(200);
        vm.prank(tipper2);
        tipping.tip{value: 2 ether}(contentHash1, creator);

        IEpixTipping.ContentInfo memory info = tipping.getContentInfo(contentHash1);
        assertEq(info.recentCount, 2);

        assertEq(info.last3[0].tipper, tipper2);
        assertEq(info.last3[0].amount, 2 ether);
        assertEq(info.last3[1].tipper, tipper1);
        assertEq(info.last3[1].amount, 1 ether);
    }

    // -----------------------------------------------------------------------
    // View functions
    // -----------------------------------------------------------------------

    function test_getContentSummary() public {
        vm.prank(tipper1);
        tipping.tip{value: 1 ether}(contentHash1, creator);
        vm.prank(tipper2);
        tipping.tip{value: 2 ether}(contentHash1, creator);

        (address storedCreator, uint256 totalAmount, uint32 uniqueTippers) = tipping.getContentSummary(contentHash1);

        assertEq(storedCreator, creator);
        assertEq(totalAmount, 3 ether);
        assertEq(uniqueTippers, 2);
    }

    function test_getTipperAmount() public {
        vm.prank(tipper1);
        tipping.tip{value: 1 ether}(contentHash1, creator);
        vm.prank(tipper1);
        tipping.tip{value: 2.5 ether}(contentHash1, creator);

        uint256 amount = tipping.getTipperAmount(contentHash1, tipper1);
        assertEq(amount, 3.5 ether);

        // Untipped address returns 0
        uint256 noAmount = tipping.getTipperAmount(contentHash1, tipper2);
        assertEq(noAmount, 0);
    }

    function test_computeContentHash() public view {
        bytes32 expected = keccak256(abi.encode("epix1talk58lw26c0cyrtuu8axptne2p6zf33s7xxwu", "mud.epix", "42"));
        bytes32 computed = tipping.computeContentHash("epix1talk58lw26c0cyrtuu8axptne2p6zf33s7xxwu", "mud.epix", "42");
        assertEq(computed, expected);
    }

    function test_getContentInfo_fullStats() public {
        vm.warp(1000);
        vm.prank(tipper1);
        tipping.tip{value: 5 ether}(contentHash1, creator);

        vm.warp(2000);
        vm.prank(tipper2);
        tipping.tip{value: 3 ether}(contentHash1, creator);

        vm.warp(3000);
        vm.prank(tipper3);
        tipping.tip{value: 7 ether}(contentHash1, creator);

        IEpixTipping.ContentInfo memory info = tipping.getContentInfo(contentHash1);

        assertEq(info.creator, creator);
        assertEq(info.totalAmount, 15 ether);
        assertEq(info.uniqueTippers, 3);
        assertEq(info.topCount, 3);
        assertEq(info.recentCount, 3);

        // Top 3 descending: tipper3 (7), tipper1 (5), tipper2 (3)
        assertEq(info.top3[0].tipper, tipper3);
        assertEq(info.top3[0].amount, 7 ether);
        assertEq(info.top3[0].xidName, "charlie.epix");
        assertEq(info.top3[1].tipper, tipper1);
        assertEq(info.top3[1].amount, 5 ether);
        assertEq(info.top3[1].xidName, "alice.epix");
        assertEq(info.top3[2].tipper, tipper2);
        assertEq(info.top3[2].amount, 3 ether);
        assertEq(info.top3[2].xidName, "bob.epix");

        // Last 3 reverse chronological: tipper3, tipper2, tipper1
        assertEq(info.last3[0].tipper, tipper3);
        assertEq(info.last3[0].timestamp, 3000);
        assertEq(info.last3[0].xidName, "charlie.epix");
        assertEq(info.last3[1].tipper, tipper2);
        assertEq(info.last3[1].timestamp, 2000);
        assertEq(info.last3[1].xidName, "bob.epix");
        assertEq(info.last3[2].tipper, tipper1);
        assertEq(info.last3[2].timestamp, 1000);
        assertEq(info.last3[2].xidName, "alice.epix");
    }

    // -----------------------------------------------------------------------
    // Untipped content returns empty/zero
    // -----------------------------------------------------------------------

    function test_untippedContent_returnsDefaults() public view {
        bytes32 untipped = keccak256("untipped");

        (address c, uint256 total, uint32 unique) = tipping.getContentSummary(untipped);
        assertEq(c, address(0));
        assertEq(total, 0);
        assertEq(unique, 0);

        IEpixTipping.ContentInfo memory info = tipping.getContentInfo(untipped);
        assertEq(info.creator, address(0));
        assertEq(info.topCount, 0);
        assertEq(info.recentCount, 0);
    }

    // -----------------------------------------------------------------------
    // Multiple content hashes are independent
    // -----------------------------------------------------------------------

    function test_getContentSummaryBatch() public {
        bytes32 hash2 = keccak256(abi.encode("other-content"));
        bytes32 hash3 = keccak256(abi.encode("untipped-content"));
        address creator2 = makeAddr("creator2");

        vm.prank(tipper1);
        tipping.tip{value: 1 ether}(contentHash1, creator);
        vm.prank(tipper2);
        tipping.tip{value: 3 ether}(contentHash1, creator);

        vm.prank(tipper1);
        tipping.tip{value: 5 ether}(hash2, creator2);

        // Batch query 3 hashes (2 tipped, 1 untipped)
        bytes32[] memory hashes = new bytes32[](3);
        hashes[0] = contentHash1;
        hashes[1] = hash2;
        hashes[2] = hash3;

        (address[] memory creators, uint256[] memory totals, uint32[] memory uniques) =
            tipping.getContentSummaryBatch(hashes);

        assertEq(creators.length, 3);

        // contentHash1: 2 tippers, 4 ether total
        assertEq(creators[0], creator);
        assertEq(totals[0], 4 ether);
        assertEq(uniques[0], 2);

        // hash2: 1 tipper, 5 ether total
        assertEq(creators[1], creator2);
        assertEq(totals[1], 5 ether);
        assertEq(uniques[1], 1);

        // hash3: untipped
        assertEq(creators[2], address(0));
        assertEq(totals[2], 0);
        assertEq(uniques[2], 0);
    }

    function test_getTipperCount() public {
        assertEq(tipping.getTipperCount(contentHash1), 0);

        vm.prank(tipper1);
        tipping.tip{value: 1 ether}(contentHash1, creator);
        assertEq(tipping.getTipperCount(contentHash1), 1);

        // Same tipper again — count stays 1
        vm.prank(tipper1);
        tipping.tip{value: 1 ether}(contentHash1, creator);
        assertEq(tipping.getTipperCount(contentHash1), 1);

        vm.prank(tipper2);
        tipping.tip{value: 1 ether}(contentHash1, creator);
        assertEq(tipping.getTipperCount(contentHash1), 2);
    }

    function test_getTipperCountBatch() public {
        bytes32 hash2 = keccak256(abi.encode("other-content"));
        bytes32 hash3 = keccak256(abi.encode("untipped-content"));
        address creator2 = makeAddr("creator2");

        vm.prank(tipper1);
        tipping.tip{value: 1 ether}(contentHash1, creator);
        vm.prank(tipper2);
        tipping.tip{value: 1 ether}(contentHash1, creator);
        vm.prank(tipper3);
        tipping.tip{value: 1 ether}(contentHash1, creator);

        vm.prank(tipper1);
        tipping.tip{value: 1 ether}(hash2, creator2);

        bytes32[] memory hashes = new bytes32[](3);
        hashes[0] = contentHash1;
        hashes[1] = hash2;
        hashes[2] = hash3;

        uint32[] memory counts = tipping.getTipperCountBatch(hashes);
        assertEq(counts.length, 3);
        assertEq(counts[0], 3); // 3 unique tippers
        assertEq(counts[1], 1); // 1 tipper
        assertEq(counts[2], 0); // untipped
    }

    function test_separateContentHashes_independent() public {
        bytes32 hash2 = keccak256("other-content");
        address creator2 = makeAddr("creator2");

        vm.prank(tipper1);
        tipping.tip{value: 1 ether}(contentHash1, creator);

        vm.prank(tipper1);
        tipping.tip{value: 5 ether}(hash2, creator2);

        (address c1, uint256 t1,) = tipping.getContentSummary(contentHash1);
        (address c2, uint256 t2,) = tipping.getContentSummary(hash2);

        assertEq(c1, creator);
        assertEq(t1, 1 ether);
        assertEq(c2, creator2);
        assertEq(t2, 5 ether);
    }
}
