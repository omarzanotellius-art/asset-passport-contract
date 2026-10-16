// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test, Vm} from "forge-std/src/Test.sol";
import {AssetPassport} from "../contracts/AssetPassport.sol";

/// Stage 1 part D: entries and confirmation. Each rule (D1-D14) tested both ways;
/// D10 and D15 are also covered by AssetPassport.interface.test.ts.
contract AssetPassportPartDTest is Test {
    AssetPassport passport;
    uint256 asset;
    address halvern = makeAddr("Halvern Capital");
    address pellam = makeAddr("Pellam Asset Services");
    address brennick = makeAddr("Brennick O&M");
    address dalbeck = makeAddr("Dalbeck Solar Services");
    address stranger = makeAddr("Stranger");

    uint64 constant APR_2022 = 1648771200;
    uint64 constant AUG_2022 = 1659312000;
    string constant H_CABLE = "Cable section C: further work";

    function setUp() public {
        vm.warp(1792108800); // Oct 2026
        passport = new AssetPassport();
        AssetPassport.Identity memory id;
        id.name = "Verrow Solar"; id.solar = true; id.state = "California";
        id.county = "Fresno County"; id.capacityKwAc = 10_000;
        vm.prank(halvern);
        asset = passport.registerAsset(id);
        join(pellam, AssetPassport.Role.AssetManager, "Pellam Asset Services");
        join(brennick, AssetPassport.Role.OmProvider, "Brennick O&M");
    }

    function join(address w, AssetPassport.Role r, string memory company) internal {
        vm.prank(halvern);
        passport.inviteRole(asset, w, r, company);
        vm.prank(w);
        passport.acceptRole(asset);
    }

    function locked(uint8 category, string memory headline) internal pure returns (AssetPassport.EntryInput memory e) {
        e.category = category; e.eventDate = APR_2022; e.headlineFingerprint = sha256(bytes(headline));
        e.equipmentRef = "Cable section C";
    }

    function open(uint8 category, string memory headline) internal pure returns (AssetPassport.EntryInput memory e) {
        e.category = category; e.eventDate = APR_2022; e.headline = headline;
    }

    function submit(address by, AssetPassport.EntryInput memory e) internal returns (uint256 id) {
        vm.prank(by);
        id = passport.submitEntry(asset, e);
    }

    function entry(uint256 id) internal view returns (AssetPassport.Entry memory) {
        return passport.getEntry(asset, id);
    }

    // ---------- D1: holder and active members submit; others cannot ----------

    function test_D1_holder_and_active_members_can_submit() public {
        submit(halvern, open(5, "Warranty claim opened"));
        submit(pellam, locked(9, "Production 2022"));
        submit(brennick, locked(3, H_CABLE));
        assertEq(passport.entryCount(asset), 3);
    }

    function test_D1_strangers_pending_and_revoked_members_cannot_submit() public {
        // build the entry first: sha256 is itself a call, and must not be the one under test
        AssetPassport.EntryInput memory e = locked(3, H_CABLE);
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.NotAuthorized.selector, stranger));
        passport.submitEntry(asset, e);
        vm.prank(halvern);
        passport.inviteRole(asset, dalbeck, AssetPassport.Role.OmProvider, "Dalbeck Solar Services"); // pending
        vm.prank(dalbeck);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.NotAuthorized.selector, dalbeck));
        passport.submitEntry(asset, e);
        vm.prank(halvern);
        passport.revokeRole(asset, brennick);
        vm.prank(brennick);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.NotAuthorized.selector, brennick));
        passport.submitEntry(asset, e);
    }

    // ---------- D2: categories restricted by role ----------

    function test_D2_om_provider_writes_only_2_3_4_13() public {
        uint8[4] memory allowed = [2, 3, 4, 13];
        for (uint256 i = 0; i < 4; i++) submit(brennick, locked(allowed[i], H_CABLE));
        uint8[10] memory denied = [1, 5, 6, 7, 8, 9, 10, 11, 12, 14];
        for (uint256 i = 0; i < 10; i++) {
            AssetPassport.EntryInput memory e = locked(denied[i], H_CABLE); // before the prank
            vm.prank(brennick);
            vm.expectRevert(abi.encodeWithSelector(AssetPassport.CategoryNotAllowed.selector, denied[i]));
            passport.submitEntry(asset, e);
        }
    }

    function test_D2_holder_and_asset_manager_write_all_14() public {
        for (uint8 c = 1; c <= 14; c++) {
            submit(halvern, open(c, "Holder entry"));
            submit(pellam, locked(c, "Manager entry"));
        }
        assertEq(passport.entryCount(asset), 28);
    }

    // ---------- D3: category 1-14 ----------

    function test_D3_category_0_and_15_rejected() public {
        vm.prank(halvern);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.InvalidCategory.selector, 0));
        passport.submitEntry(asset, open(0, "Zero"));
        vm.prank(halvern);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.InvalidCategory.selector, 15));
        passport.submitEntry(asset, open(15, "Fifteen"));
        submit(halvern, open(14, "Insurance policy in force"));
    }

    // ---------- D4: event date and recorded date ----------

    function test_D4_recorded_date_is_block_time_event_date_as_given() public {
        uint256 id = submit(brennick, locked(3, H_CABLE));
        assertEq(entry(id).eventDate, APR_2022);
        assertEq(entry(id).recordedAt, uint64(block.timestamp));
    }

    function test_D4_future_or_zero_event_date_rejected_today_accepted() public {
        AssetPassport.EntryInput memory e = open(3, "Corrective work");
        e.eventDate = uint64(block.timestamp + 1);
        vm.prank(halvern);
        vm.expectRevert(AssetPassport.DateInFuture.selector);
        passport.submitEntry(asset, e);
        e.eventDate = 0;
        vm.prank(halvern);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.EmptyField.selector, "eventDate"));
        passport.submitEntry(asset, e);
        e.eventDate = uint64(block.timestamp);
        submit(halvern, e);
    }

    function test_D4_late_recording_shows_in_the_two_dates() public {
        AssetPassport.EntryInput memory e = open(3, "Corrective work, second call-out");
        e.eventDate = AUG_2022; // recorded in Oct 2026: long after the event
        uint256 id = submit(halvern, e);
        assertGt(entry(id).recordedAt - entry(id).eventDate, 30 days);
    }

    // ---------- D5: holder text vs others' fingerprint ----------

    function test_D5_holder_entry_carries_text_and_its_fingerprint() public {
        uint256 id = submit(halvern, open(5, "Warranty claim opened"));
        assertEq(entry(id).headline, "Warranty claim opened");
        assertEq(entry(id).headlineFingerprint, sha256(bytes("Warranty claim opened")));
    }

    function test_D5_holder_must_give_text_not_fingerprint() public {
        AssetPassport.EntryInput memory e = open(5, "");
        vm.prank(halvern);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.EmptyField.selector, "headline"));
        passport.submitEntry(asset, e);
        e = open(5, "Warranty claim opened");
        e.headlineFingerprint = sha256(bytes("x"));
        vm.prank(halvern);
        vm.expectRevert(AssetPassport.FingerprintNotAllowed.selector);
        passport.submitEntry(asset, e);
    }

    function test_D5_others_give_fingerprint_not_text_and_headline_stays_hidden() public {
        AssetPassport.EntryInput memory e = locked(3, H_CABLE);
        e.headline = H_CABLE;
        vm.prank(brennick);
        vm.expectRevert(AssetPassport.HeadlineNotAllowed.selector);
        passport.submitEntry(asset, e);
        e = locked(3, H_CABLE);
        e.headlineFingerprint = bytes32(0);
        vm.prank(brennick);
        vm.expectRevert(AssetPassport.MissingFingerprint.selector);
        passport.submitEntry(asset, e);
        uint256 id = submit(brennick, locked(3, H_CABLE));
        assertEq(bytes(entry(id).headline).length, 0);
        assertFalse(entry(id).confirmed);
    }

    // ---------- D6: confirmer publishes matching text ----------

    function test_D6_confirmation_publishes_matching_headline() public {
        uint256 id = submit(brennick, locked(3, H_CABLE));
        vm.prank(halvern);
        passport.confirmEntry(asset, id, H_CABLE);
        assertEq(entry(id).headline, H_CABLE);
        assertTrue(entry(id).confirmed);
    }

    function test_D6_wrong_text_rejected_even_by_one_character() public {
        uint256 id = submit(brennick, locked(3, H_CABLE));
        vm.prank(halvern);
        vm.expectRevert(AssetPassport.HeadlineMismatch.selector);
        passport.confirmEntry(asset, id, "Cable section C: further work.");
        vm.prank(halvern);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.EmptyField.selector, "headline"));
        passport.confirmEntry(asset, id, "");
        assertFalse(entry(id).confirmed);
    }

    // ---------- D7: optional fields ----------

    function test_D7_optional_fields_stored_and_may_be_empty() public {
        AssetPassport.EntryInput memory e = locked(3, H_CABLE);
        e.manifest = sha256("manifest");
        uint256 a = submit(brennick, e);
        assertEq(entry(a).manifest, sha256("manifest"));
        assertEq(entry(a).equipmentRef, "Cable section C");
        AssetPassport.EntryInput memory bare = open(10, "O&M contract renewed");
        uint256 b = submit(halvern, bare);
        assertEq(entry(b).manifest, bytes32(0));
        assertEq(bytes(entry(b).equipmentRef).length, 0);
        assertEq(entry(b).link, 0);
    }

    function test_D7_link_must_point_to_an_earlier_entry() public {
        uint256 claim = submit(halvern, open(5, "Warranty claim opened"));
        AssetPassport.EntryInput memory d = open(6, "Dispute opened over the claim");
        d.link = claim;
        uint256 dispute = submit(halvern, d);
        assertEq(entry(dispute).link, claim);
        d.link = dispute + 1; // the entry about to be created: not earlier
        vm.prank(halvern);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.InvalidLink.selector, dispute + 1));
        passport.submitEntry(asset, d);
    }

    function test_D7_equipment_ref_limited_to_100_bytes() public {
        bytes memory long = new bytes(101);
        for (uint256 i = 0; i < 101; i++) long[i] = "a";
        AssetPassport.EntryInput memory e = locked(3, H_CABLE);
        e.equipmentRef = string(long);
        vm.prank(brennick);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.TextTooLong.selector, "equipmentRef"));
        passport.submitEntry(asset, e);
    }

    // ---------- D8: who confirms ----------

    function test_D8_holder_entries_confirmed_at_once() public {
        uint256 id = submit(halvern, open(5, "Warranty claim opened"));
        assertTrue(entry(id).confirmed);
        assertEq(entry(id).confirmer, halvern);
        vm.prank(halvern);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.AlreadyConfirmed.selector, id));
        passport.confirmEntry(asset, id, "Warranty claim opened");
    }

    function test_D8_asset_manager_entries_confirmed_by_holder_only() public {
        uint256 id = submit(pellam, locked(9, "Production 2022"));
        vm.prank(pellam);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.NotAuthorized.selector, pellam));
        passport.confirmEntry(asset, id, "Production 2022");
        address quenby = makeAddr("Quenby Energy Management");
        join(quenby, AssetPassport.Role.AssetManager, "Quenby Energy Management");
        vm.prank(quenby); // another asset manager cannot either
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.NotAuthorized.selector, quenby));
        passport.confirmEntry(asset, id, "Production 2022");
        vm.prank(halvern);
        passport.confirmEntry(asset, id, "Production 2022");
    }

    function test_D8_om_entries_confirmed_by_holder_or_active_asset_manager() public {
        uint256 a = submit(brennick, locked(3, H_CABLE));
        uint256 b = submit(brennick, locked(2, "Annual visit"));
        vm.prank(pellam);
        passport.confirmEntry(asset, a, H_CABLE);
        vm.prank(halvern);
        passport.confirmEntry(asset, b, "Annual visit");
        assertEq(entry(a).confirmer, pellam);
        assertEq(entry(b).confirmer, halvern);
    }

    function test_D8_om_providers_strangers_and_revoked_managers_cannot_confirm() public {
        join(dalbeck, AssetPassport.Role.OmProvider, "Dalbeck Solar Services");
        uint256 id = submit(brennick, locked(3, H_CABLE));
        vm.prank(dalbeck);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.NotAuthorized.selector, dalbeck));
        passport.confirmEntry(asset, id, H_CABLE);
        vm.prank(brennick); // not even its own
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.NotAuthorized.selector, brennick));
        passport.confirmEntry(asset, id, H_CABLE);
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.NotAuthorized.selector, stranger));
        passport.confirmEntry(asset, id, H_CABLE);
        vm.prank(halvern);
        passport.revokeRole(asset, pellam);
        vm.prank(pellam);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.NotAuthorized.selector, pellam));
        passport.confirmEntry(asset, id, H_CABLE);
    }

    function test_D8_invited_but_not_accepted_manager_cannot_confirm() public {
        address quenby = makeAddr("Quenby Energy Management");
        vm.prank(halvern);
        passport.inviteRole(asset, quenby, AssetPassport.Role.AssetManager, "Quenby Energy Management");
        uint256 id = submit(brennick, locked(3, H_CABLE));
        vm.prank(quenby); // invited, not yet accepted: no powers
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.NotAuthorized.selector, quenby));
        passport.confirmEntry(asset, id, H_CABLE);
    }

    // ---------- D9: confirmer and time recorded ----------

    function test_D9_confirmer_and_time_recorded() public {
        uint256 id = submit(brennick, locked(3, H_CABLE));
        vm.warp(block.timestamp + 7 days);
        vm.prank(pellam);
        passport.confirmEntry(asset, id, H_CABLE);
        assertEq(entry(id).confirmer, pellam);
        assertEq(entry(id).confirmedAt, uint64(block.timestamp));
        assertEq(entry(id).confirmedAt - entry(id).recordedAt, 7 days);
    }

    // ---------- D10: nothing edited; unconfirmed stays pending ----------

    function test_D10_confirmed_entry_cannot_be_confirmed_again_with_other_text() public {
        uint256 id = submit(brennick, locked(3, H_CABLE));
        vm.prank(halvern);
        passport.confirmEntry(asset, id, H_CABLE);
        vm.prank(pellam);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.AlreadyConfirmed.selector, id));
        passport.confirmEntry(asset, id, H_CABLE);
        assertEq(entry(id).confirmer, halvern);
    }

    function test_D10_unconfirmed_entry_stays_pending_and_unchanged() public {
        uint256 id = submit(brennick, locked(3, H_CABLE));
        submit(halvern, open(2, "Annual visit"));
        vm.warp(block.timestamp + 365 days);
        AssetPassport.Entry memory e = entry(id);
        assertFalse(e.confirmed);
        assertEq(e.category, 3);
        assertEq(e.headlineFingerprint, sha256(bytes(H_CABLE)));
    }

    // ---------- D11: revoked writer's pending entries still confirmable; snapshot kept ----------

    function test_D11_revoked_writers_pending_entry_can_be_confirmed() public {
        uint256 id = submit(brennick, locked(3, H_CABLE));
        vm.prank(halvern);
        passport.revokeRole(asset, brennick);
        vm.prank(halvern);
        passport.confirmEntry(asset, id, H_CABLE);
        assertTrue(entry(id).confirmed);
    }

    function test_D11_author_role_and_company_survive_revocation() public {
        uint256 id = submit(brennick, locked(3, H_CABLE));
        vm.prank(halvern);
        passport.revokeRole(asset, brennick);
        AssetPassport.Entry memory e = entry(id);
        assertEq(e.author, brennick);
        assertEq(uint8(e.writer), uint8(AssetPassport.Writer.OmProvider));
        assertEq(e.authorCompany, "Brennick O&M");
        uint256 h = submit(halvern, open(10, "Provider changed"));
        assertEq(uint8(entry(h).writer), uint8(AssetPassport.Writer.Holder));
        assertEq(bytes(entry(h).authorCompany).length, 0);
    }

    // ---------- D12: events ----------

    function test_D12_submission_and_confirmation_events() public {
        vm.recordLogs();
        uint256 id = submit(brennick, locked(3, H_CABLE));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].topics[0], AssetPassport.EntrySubmitted.selector);
        assertEq(logs[0].topics[3], bytes32(uint256(uint160(brennick))));
        vm.expectEmit(true, true, true, true, address(passport));
        emit AssetPassport.EntryConfirmed(asset, id, pellam, H_CABLE);
        vm.prank(pellam);
        passport.confirmEntry(asset, id, H_CABLE);
    }

    function test_D12_holder_entry_emits_both_events() public {
        vm.recordLogs();
        submit(halvern, open(5, "Warranty claim opened"));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 2);
        assertEq(logs[0].topics[0], AssetPassport.EntrySubmitted.selector);
        assertEq(logs[1].topics[0], AssetPassport.EntryConfirmed.selector);
    }

    // ---------- D13 / D14: reading and numbering ----------

    function test_D13_anyone_reads_unknown_entries_rejected() public {
        submit(brennick, locked(3, H_CABLE));
        vm.prank(stranger);
        assertEq(passport.getEntry(asset, 1).category, 3);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.UnknownEntry.selector, 0));
        passport.getEntry(asset, 0);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.UnknownEntry.selector, 2));
        passport.getEntry(asset, 2);
        vm.prank(halvern);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.UnknownEntry.selector, 2));
        passport.confirmEntry(asset, 2, "x");
        vm.prank(halvern);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.UnknownAsset.selector, 99));
        passport.submitEntry(99, open(5, "x"));
    }

    function test_D14_entries_numbered_from_1_per_asset() public {
        assertEq(submit(halvern, open(5, "a")), 1);
        assertEq(submit(brennick, locked(3, H_CABLE)), 2);
        AssetPassport.Identity memory id;
        id.name = "Wildrye Solar"; id.solar = true; id.state = "California";
        id.county = "Fresno County"; id.capacityKwAc = 10_000;
        address larkmoor = makeAddr("Larkmoor Capital");
        vm.prank(larkmoor);
        uint256 other = passport.registerAsset(id);
        vm.prank(larkmoor);
        assertEq(passport.submitEntry(other, open(1, "Commissioned")), 1);
        assertEq(passport.entryCount(asset), 2);
    }
}
