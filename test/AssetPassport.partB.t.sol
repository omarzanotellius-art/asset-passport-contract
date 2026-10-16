// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test, Vm} from "forge-std/src/Test.sol";
import {AssetPassport} from "../contracts/AssetPassport.sol";

/// Stage 1 part B: equipment list and warranties. Each rule (B1-B11) tested both ways;
/// B12 is covered by AssetPassport.interface.test.ts.
contract AssetPassportPartBTest is Test {
    AssetPassport passport;
    uint256 asset;
    address holder = makeAddr("Halvern Capital");
    address pellam = makeAddr("Pellam Asset Services");
    address brennick = makeAddr("Brennick O&M");
    address stranger = makeAddr("Stranger");

    uint16 constant INVERTERS = 1;
    uint16 constant MODULES = 2;
    uint64 constant JUL_2021 = 1625097600;
    uint64 constant SEP_2023 = 1693526400;
    uint64 constant JUL_2026 = 1782864000;
    uint64 constant JUL_2031 = 1940630400;
    uint64 constant SEP_2033 = 2009145600;

    function setUp() public {
        vm.warp(1792108800); // Oct 2026
        passport = new AssetPassport();
        AssetPassport.Identity memory id;
        id.name = "Verrow Solar"; id.solar = true; id.state = "California";
        id.county = "Fresno County"; id.capacityKwAc = 10_000;
        vm.prank(holder);
        asset = passport.registerAsset(id);
        vm.prank(holder);
        passport.inviteRole(asset, pellam, AssetPassport.Role.AssetManager, "Pellam Asset Services");
        vm.prank(pellam);
        passport.acceptRole(asset);
        vm.prank(holder);
        passport.inviteRole(asset, brennick, AssetPassport.Role.OmProvider, "Brennick O&M");
        vm.prank(brennick);
        passport.acceptRole(asset);
    }

    function inverter(string memory name) internal pure returns (AssetPassport.UnitInput memory u) {
        u.name = name; u.system = INVERTERS; u.oem = "Brindle Inverter Systems"; u.model = "CI-3400";
        u.rating = "3,400 kWac"; u.quantity = 1; u.inService = JUL_2021;
        u.warrantyStart = JUL_2021; u.warrantyEnd = JUL_2026;
    }

    function addAsHolder(AssetPassport.UnitInput memory u) internal returns (uint256 id) {
        vm.prank(holder);
        (, id) = passport.addUnit(asset, u);
    }

    function unit(uint256 id) internal view returns (AssetPassport.Unit memory u, uint64 end) {
        return passport.getUnit(asset, id);
    }

    // ---------- B1: holder applies directly; asset manager proposes; nobody else ----------

    function test_B1_holder_change_applies_at_once() public {
        vm.prank(holder);
        (bool applied, uint256 id) = passport.addUnit(asset, inverter("Inverter 1"));
        assertTrue(applied);
        assertEq(id, 1);
        assertEq(passport.unitCount(asset), 1);
    }

    function test_B1_asset_manager_change_waits_for_holder_confirmation() public {
        vm.prank(pellam);
        (bool applied, uint256 pid) = passport.addUnit(asset, inverter("Inverter 1"));
        assertFalse(applied);
        assertEq(passport.unitCount(asset), 0); // not applied yet
        vm.prank(holder);
        passport.confirmProposal(asset, pid);
        assertEq(passport.unitCount(asset), 1);
        (AssetPassport.Unit memory u,) = unit(1);
        assertEq(u.spec.name, "Inverter 1");
    }

    function test_B1_om_provider_and_strangers_cannot_change_equipment() public {
        vm.prank(brennick);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.NotAuthorized.selector, brennick));
        passport.addUnit(asset, inverter("Inverter 1"));
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.NotAuthorized.selector, stranger));
        passport.addUnit(asset, inverter("Inverter 1"));
    }

    function test_B1_only_holder_confirms_and_only_proposer_withdraws() public {
        vm.prank(pellam);
        (, uint256 pid) = passport.addUnit(asset, inverter("Inverter 1"));
        vm.prank(pellam); // the asset manager cannot confirm its own proposal (D58)
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.NotAuthorized.selector, pellam));
        passport.confirmProposal(asset, pid);
        vm.prank(holder); // the holder cannot withdraw it (no declining)
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.NotAuthorized.selector, holder));
        passport.withdrawProposal(asset, pid);
        vm.prank(pellam);
        passport.withdrawProposal(asset, pid);
        assertEq(uint8(passport.getProposal(asset, pid).status), uint8(AssetPassport.ProposalStatus.Withdrawn));
    }

    function test_B1_withdrawn_or_confirmed_proposals_cannot_be_confirmed_again() public {
        vm.prank(pellam);
        (, uint256 a) = passport.addUnit(asset, inverter("Inverter 1"));
        vm.prank(pellam);
        passport.withdrawProposal(asset, a);
        vm.prank(holder);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.ProposalNotPending.selector, a));
        passport.confirmProposal(asset, a);
        vm.prank(pellam);
        (, uint256 b) = passport.addUnit(asset, inverter("Inverter 2"));
        vm.prank(holder);
        passport.confirmProposal(asset, b);
        vm.prank(holder);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.ProposalNotPending.selector, b));
        passport.confirmProposal(asset, b);
        assertEq(passport.unitCount(asset), 1);
    }

    function test_B1_revoked_managers_pending_proposal_can_still_be_confirmed() public {
        vm.prank(pellam);
        (, uint256 pid) = passport.addUnit(asset, inverter("Inverter 1"));
        vm.prank(holder);
        passport.revokeRole(asset, pellam);
        vm.prank(pellam); // but it can no longer propose
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.NotAuthorized.selector, pellam));
        passport.addUnit(asset, inverter("Inverter 2"));
        vm.prank(holder);
        passport.confirmProposal(asset, pid);
        assertEq(passport.unitCount(asset), 1);
    }

    function test_B1_proposals_for_replacement_and_extension_work_too() public {
        uint256 inv = addAsHolder(inverter("Inverter 2"));
        AssetPassport.UnitInput memory n = inverter("Inverter 2");
        n.inService = SEP_2023; n.warrantyStart = SEP_2023; n.warrantyEnd = SEP_2033;
        vm.prank(pellam);
        (, uint256 p1) = passport.replaceUnit(asset, inv, n, SEP_2023);
        vm.prank(pellam);
        (, uint256 p2) = passport.extendWarranty(asset, inv, JUL_2031);
        vm.prank(holder);
        passport.confirmProposal(asset, p2); // extend first, while not yet replaced
        vm.prank(holder);
        passport.confirmProposal(asset, p1);
        (AssetPassport.Unit memory old, uint64 end) = unit(inv);
        assertEq(old.replacedBy, 2);
        assertEq(end, JUL_2031);
    }

    function test_B1_proposal_rechecked_when_confirmed() public {
        uint256 inv = addAsHolder(inverter("Inverter 2"));
        AssetPassport.UnitInput memory n = inverter("Inverter 2");
        n.inService = SEP_2023;
        vm.prank(pellam);
        (, uint256 ext) = passport.extendWarranty(asset, inv, JUL_2031);
        vm.prank(holder);
        passport.replaceUnit(asset, inv, n, SEP_2023); // unit replaced meanwhile
        vm.prank(holder);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.AlreadyReplaced.selector, inv));
        passport.confirmProposal(asset, ext);
        assertEq(uint8(passport.getProposal(asset, ext).status), uint8(AssetPassport.ProposalStatus.Pending));
    }

    // ---------- B2: unit fields ----------

    function test_B2_fields_stored_exactly() public {
        AssetPassport.UnitInput memory d = inverter("Drives and controllers");
        d.system = 4; d.quantity = 267; d.isPart = true; d.model = ""; d.rating = "";
        uint256 id = addAsHolder(d);
        (AssetPassport.Unit memory u,) = unit(id);
        assertEq(u.spec.name, "Drives and controllers");
        assertEq(u.spec.oem, "Brindle Inverter Systems");
        assertEq(u.spec.quantity, 267);
        assertTrue(u.spec.isPart);
        assertEq(u.spec.inService, JUL_2021);
    }

    function test_B2_required_fields_and_quantity_enforced() public {
        AssetPassport.UnitInput memory u = inverter("");
        vm.prank(holder);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.EmptyField.selector, "name"));
        passport.addUnit(asset, u);
        u = inverter("Inverter 1"); u.oem = "";
        vm.prank(holder);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.EmptyField.selector, "oem"));
        passport.addUnit(asset, u);
        u = inverter("Inverter 1"); u.quantity = 0;
        vm.prank(holder);
        vm.expectRevert(AssetPassport.ZeroQuantity.selector);
        passport.addUnit(asset, u);
        u = inverter("Inverter 1"); u.inService = 0;
        vm.prank(holder);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.EmptyField.selector, "inService"));
        passport.addUnit(asset, u);
    }

    function test_B2_text_limited_to_100_bytes() public {
        bytes memory long = new bytes(101);
        for (uint256 i = 0; i < 101; i++) long[i] = "a";
        AssetPassport.UnitInput memory u = inverter("Inverter 1");
        u.model = string(long);
        vm.prank(holder);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.TextTooLong.selector, "model"));
        passport.addUnit(asset, u);
        u = inverter("Inverter 1"); u.rating = string(long);
        vm.prank(holder);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.TextTooLong.selector, "rating"));
        passport.addUnit(asset, u);
    }

    // ---------- B3: numbering per asset ----------

    function test_B3_units_numbered_from_1_within_each_asset() public {
        assertEq(addAsHolder(inverter("Inverter 1")), 1);
        assertEq(addAsHolder(inverter("Inverter 2")), 2);
        AssetPassport.Identity memory id;
        id.name = "Wildrye Solar"; id.solar = true; id.state = "California";
        id.county = "Fresno County"; id.capacityKwAc = 10_000;
        address larkmoor = makeAddr("Larkmoor Capital");
        vm.prank(larkmoor);
        uint256 other = passport.registerAsset(id);
        vm.prank(larkmoor);
        (, uint256 first) = passport.addUnit(other, inverter("Inverter 1"));
        assertEq(first, 1); // separate numbering per asset
        assertEq(passport.unitCount(asset), 2);
    }

    // ---------- B4: system number; 0 rejected, others accepted ----------

    function test_B4_system_zero_rejected_any_other_accepted() public {
        AssetPassport.UnitInput memory u = inverter("Inverter 1");
        u.system = 0;
        vm.prank(holder);
        vm.expectRevert(AssetPassport.InvalidSystem.selector);
        passport.addUnit(asset, u);
        u.system = 42; // a future system number needs no redeploy
        addAsHolder(u);
    }

    // ---------- B5: dates not in the future ----------

    function test_B5_future_in_service_date_rejected_today_accepted() public {
        AssetPassport.UnitInput memory u = inverter("Inverter 1");
        u.inService = uint64(block.timestamp + 1);
        vm.prank(holder);
        vm.expectRevert(AssetPassport.DateInFuture.selector);
        passport.addUnit(asset, u);
        u.inService = uint64(block.timestamp);
        addAsHolder(u);
    }

    function test_B5_future_replacement_date_rejected() public {
        uint256 inv = addAsHolder(inverter("Inverter 2"));
        vm.prank(holder);
        vm.expectRevert(AssetPassport.DateInFuture.selector);
        passport.replaceUnit(asset, inv, inverter("Inverter 2"), uint64(block.timestamp + 1));
    }

    // ---------- B6: replacement in one action, linked both ways ----------

    function test_B6_replacement_marks_old_and_adds_new_linked_both_ways() public {
        addAsHolder(inverter("Inverter 1"));
        uint256 inv = addAsHolder(inverter("Inverter 2"));
        AssetPassport.UnitInput memory n = inverter("Inverter 2");
        n.inService = SEP_2023; n.warrantyStart = SEP_2023; n.warrantyEnd = SEP_2033;
        vm.prank(holder);
        (, uint256 newId) = passport.replaceUnit(asset, inv, n, SEP_2023);
        (AssetPassport.Unit memory old,) = unit(inv);
        (AssetPassport.Unit memory fresh,) = unit(newId);
        assertEq(old.replacedAt, SEP_2023);
        assertEq(old.replacedBy, newId);
        assertEq(fresh.replaces, inv);
        assertEq(fresh.replacedAt, 0);
        assertEq(passport.unitCount(asset), 3);
    }

    function test_B6_cannot_replace_twice_or_across_systems_or_before_in_service() public {
        uint256 inv = addAsHolder(inverter("Inverter 2"));
        AssetPassport.UnitInput memory m = inverter("PV modules");
        m.system = MODULES;
        vm.prank(holder);
        vm.expectRevert(AssetPassport.SystemMismatch.selector);
        passport.replaceUnit(asset, inv, m, SEP_2023);
        vm.prank(holder);
        vm.expectRevert(AssetPassport.ReplacementBeforeInService.selector);
        passport.replaceUnit(asset, inv, inverter("Inverter 2"), JUL_2021 - 1);
        vm.prank(holder);
        passport.replaceUnit(asset, inv, inverter("Inverter 2"), SEP_2023);
        vm.prank(holder);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.AlreadyReplaced.selector, inv));
        passport.replaceUnit(asset, inv, inverter("Inverter 2"), SEP_2023);
    }

    // ---------- B7: warranty and extensions ----------

    function test_B7_warranty_optional_but_end_must_follow_start() public {
        AssetPassport.UnitInput memory u = inverter("Inverter 1");
        u.warrantyStart = 0; u.warrantyEnd = 0;
        uint256 id = addAsHolder(u); // no warranty is fine
        (, uint64 end) = unit(id);
        assertEq(end, 0);
        u.warrantyStart = JUL_2026; u.warrantyEnd = JUL_2026;
        vm.prank(holder);
        vm.expectRevert(AssetPassport.InvalidWarranty.selector);
        passport.addUnit(asset, u);
        u.warrantyStart = JUL_2026; u.warrantyEnd = JUL_2021;
        vm.prank(holder);
        vm.expectRevert(AssetPassport.InvalidWarranty.selector);
        passport.addUnit(asset, u);
    }

    function test_B7_extensions_appended_and_must_push_end_later() public {
        uint256 inv = addAsHolder(inverter("Inverter 1"));
        vm.prank(holder);
        vm.expectRevert(AssetPassport.ExtensionNotLater.selector);
        passport.extendWarranty(asset, inv, JUL_2026); // same end
        vm.prank(holder);
        passport.extendWarranty(asset, inv, JUL_2031);
        vm.prank(holder);
        vm.expectRevert(AssetPassport.ExtensionNotLater.selector);
        passport.extendWarranty(asset, inv, JUL_2026 + 1); // later than original, earlier than current
        uint64[] memory ext = passport.warrantyExtensions(asset, inv);
        assertEq(ext.length, 1);
        assertEq(ext[0], JUL_2031);
        (AssetPassport.Unit memory u, uint64 end) = unit(inv);
        assertEq(end, JUL_2031);
        assertEq(u.spec.warrantyEnd, JUL_2026); // the original end is never edited
    }

    function test_B7_no_extension_without_warranty_or_after_replacement() public {
        AssetPassport.UnitInput memory u = inverter("Inverter 1");
        u.warrantyStart = 0; u.warrantyEnd = 0;
        uint256 bare = addAsHolder(u);
        vm.prank(holder);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.NoWarranty.selector, bare));
        passport.extendWarranty(asset, bare, JUL_2031);
        uint256 inv = addAsHolder(inverter("Inverter 2"));
        vm.prank(holder);
        passport.replaceUnit(asset, inv, inverter("Inverter 2"), SEP_2023);
        vm.prank(holder);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.AlreadyReplaced.selector, inv));
        passport.extendWarranty(asset, inv, JUL_2031);
    }

    // ---------- B8: replaced unit keeps its history; new unit has its own warranty ----------

    function test_B8_old_unit_keeps_record_and_new_unit_has_own_warranty() public {
        uint256 inv = addAsHolder(inverter("Inverter 2"));
        vm.prank(holder);
        passport.extendWarranty(asset, inv, JUL_2031);
        AssetPassport.UnitInput memory n = inverter("Inverter 2");
        n.inService = SEP_2023; n.warrantyStart = SEP_2023; n.warrantyEnd = SEP_2033;
        vm.prank(holder);
        (, uint256 newId) = passport.replaceUnit(asset, inv, n, SEP_2023);
        (AssetPassport.Unit memory old, uint64 oldEnd) = unit(inv);
        assertEq(old.spec.name, "Inverter 2");
        assertEq(old.spec.inService, JUL_2021);
        assertEq(oldEnd, JUL_2031);
        assertEq(passport.warrantyExtensions(asset, inv).length, 1);
        (, uint64 newEnd) = unit(newId);
        assertEq(newEnd, SEP_2033);
        assertEq(passport.warrantyExtensions(asset, newId).length, 0);
    }

    // ---------- B9: events ----------

    function test_B9_events_for_direct_changes_name_the_author() public {
        AssetPassport.UnitInput memory u = inverter("Inverter 1");
        vm.expectEmit(true, true, true, true, address(passport));
        emit AssetPassport.UnitAdded(asset, 1, u, holder);
        addAsHolder(u);
        vm.expectEmit(true, true, true, true, address(passport));
        emit AssetPassport.WarrantyExtended(asset, 1, JUL_2031, holder);
        vm.prank(holder);
        passport.extendWarranty(asset, 1, JUL_2031);
        vm.expectEmit(true, true, true, true, address(passport));
        emit AssetPassport.UnitReplaced(asset, 1, 2, SEP_2023, holder);
        vm.prank(holder);
        passport.replaceUnit(asset, 1, inverter("Inverter 1"), SEP_2023);
    }

    function test_B9_confirmed_proposal_credits_the_asset_manager() public {
        AssetPassport.UnitInput memory u = inverter("Inverter 1");
        vm.expectEmit(true, true, true, true, address(passport));
        emit AssetPassport.ProposalMade(asset, 1, AssetPassport.ProposalKind.AddUnit, pellam);
        vm.prank(pellam);
        passport.addUnit(asset, u);
        vm.expectEmit(true, true, false, true, address(passport));
        emit AssetPassport.ProposalConfirmed(asset, 1);
        vm.expectEmit(true, true, true, true, address(passport));
        emit AssetPassport.UnitAdded(asset, 1, u, pellam); // author = proposer, not the holder
        vm.prank(holder);
        passport.confirmProposal(asset, 1);
    }

    function test_B9_withdrawal_emits_event() public {
        vm.prank(pellam);
        passport.addUnit(asset, inverter("Inverter 1"));
        vm.expectEmit(true, true, false, true, address(passport));
        emit AssetPassport.ProposalWithdrawn(asset, 1);
        vm.prank(pellam);
        passport.withdrawProposal(asset, 1);
    }

    // ---------- B10: units fixed; only replacement mark and extensions change ----------

    function test_B10_unit_fields_unchanged_by_later_activity() public {
        uint256 inv = addAsHolder(inverter("Inverter 2"));
        addAsHolder(inverter("Inverter 3"));
        vm.prank(holder);
        passport.extendWarranty(asset, inv, JUL_2031);
        vm.prank(holder);
        passport.replaceUnit(asset, inv, inverter("Inverter 2b"), SEP_2023);
        (AssetPassport.Unit memory u,) = unit(inv);
        assertEq(u.spec.name, "Inverter 2");
        assertEq(u.spec.model, "CI-3400");
        assertEq(u.spec.warrantyEnd, JUL_2026);
        assertEq(u.spec.quantity, 1);
    }

    // ---------- B11: anyone reads; unknown numbers rejected ----------

    function test_B11_anyone_can_read_units_and_proposals() public {
        addAsHolder(inverter("Inverter 1"));
        vm.prank(pellam);
        passport.addUnit(asset, inverter("Inverter 2"));
        vm.prank(stranger);
        (AssetPassport.Unit memory u,) = passport.getUnit(asset, 1);
        assertEq(u.spec.name, "Inverter 1");
        vm.prank(stranger);
        AssetPassport.Proposal memory p = passport.getProposal(asset, 1);
        assertEq(p.proposer, pellam);
        assertEq(uint8(p.kind), uint8(AssetPassport.ProposalKind.AddUnit));
    }

    function test_B11_unknown_unit_proposal_or_asset_rejected() public {
        addAsHolder(inverter("Inverter 1"));
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.UnknownUnit.selector, 0));
        passport.getUnit(asset, 0);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.UnknownUnit.selector, 2));
        passport.getUnit(asset, 2);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.UnknownUnit.selector, 2));
        passport.warrantyExtensions(asset, 2);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.UnknownProposal.selector, 1));
        passport.getProposal(asset, 1);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.UnknownAsset.selector, 99));
        passport.getUnit(99, 1);
        vm.prank(holder);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.UnknownUnit.selector, 5));
        passport.replaceUnit(asset, 5, inverter("Inverter 5"), SEP_2023);
        vm.prank(holder);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.UnknownAsset.selector, 99));
        passport.addUnit(99, inverter("Inverter 1"));
    }
}
