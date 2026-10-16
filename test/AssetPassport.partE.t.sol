// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test, Vm} from "forge-std/src/Test.sol";
import {AssetPassport} from "../contracts/AssetPassport.sol";

/// Stage 1 part E: control transfer. Each rule (E1-E10) tested both ways;
/// E11 is covered by AssetPassport.interface.test.ts.
contract AssetPassportPartETest is Test {
    AssetPassport passport;
    uint256 asset;
    address halvern = makeAddr("Halvern Capital");
    address ostrell = makeAddr("Ostrell Capital");
    address other = makeAddr("Other Buyer");
    address pellam = makeAddr("Pellam Asset Services");
    address brennick = makeAddr("Brennick O&M");
    address stranger = makeAddr("Stranger");

    uint64 constant MAY_2024 = 1714521600;
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
        vm.prank(passport.holderOf(asset));
        passport.inviteRole(asset, w, r, company);
        vm.prank(w);
        passport.acceptRole(asset);
    }

    function propose(address to) internal {
        vm.prank(passport.holderOf(asset));
        passport.proposeTransfer(asset, to);
    }

    function transferTo(address to) internal {
        propose(to);
        vm.prank(to);
        passport.acceptTransfer(asset);
    }

    function omEntry() internal returns (uint256 id) {
        AssetPassport.EntryInput memory e;
        e.category = 3; e.eventDate = MAY_2024; e.headlineFingerprint = sha256(bytes(H_CABLE));
        e.equipmentRef = "Cable section C";
        vm.prank(brennick);
        id = passport.submitEntry(asset, e);
    }

    function holderEntry(address h, string memory headline) internal returns (uint256 id) {
        AssetPassport.EntryInput memory e;
        e.category = 5; e.eventDate = MAY_2024; e.headline = headline;
        vm.prank(h);
        id = passport.submitEntry(asset, e);
    }

    function unit() internal pure returns (AssetPassport.UnitInput memory u) {
        u.name = "Inverter 1"; u.system = 1; u.oem = "Brindle Inverter Systems";
        u.quantity = 1; u.inService = 1625097600;
    }

    // ---------- E1: propose, then accept ----------

    function test_E1_control_moves_only_on_acceptance() public {
        propose(ostrell);
        assertEq(passport.holderOf(asset), halvern); // not yet
        vm.prank(ostrell);
        passport.acceptTransfer(asset);
        assertEq(passport.holderOf(asset), ostrell);
    }

    function test_E1_only_holder_proposes_only_proposed_wallet_accepts() public {
        vm.prank(pellam);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.NotAuthorized.selector, pellam));
        passport.proposeTransfer(asset, ostrell);
        propose(ostrell);
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.NotAuthorized.selector, other));
        passport.acceptTransfer(asset);
        vm.prank(halvern); // not even the holder can accept on the buyer's behalf
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.NotAuthorized.selector, halvern));
        passport.acceptTransfer(asset);
    }

    function test_E1_nothing_to_accept_without_a_proposal() public {
        vm.prank(ostrell);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.NotAuthorized.selector, ostrell));
        passport.acceptTransfer(asset);
    }

    // ---------- E2: cancel; one pending; a new proposal replaces it ----------

    function test_E2_holder_can_cancel_and_cancelled_proposal_cannot_be_accepted() public {
        propose(ostrell);
        vm.prank(halvern);
        passport.cancelTransfer(asset);
        assertEq(passport.pendingHolderOf(asset), address(0));
        vm.prank(ostrell);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.NotAuthorized.selector, ostrell));
        passport.acceptTransfer(asset);
    }

    function test_E2_only_holder_cancels_and_only_when_pending() public {
        vm.prank(halvern);
        vm.expectRevert(AssetPassport.NoPendingTransfer.selector);
        passport.cancelTransfer(asset);
        propose(ostrell);
        vm.prank(ostrell);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.NotAuthorized.selector, ostrell));
        passport.cancelTransfer(asset);
    }

    function test_E2_new_proposal_replaces_the_previous_one() public {
        propose(ostrell);
        propose(other);
        assertEq(passport.pendingHolderOf(asset), other);
        vm.prank(ostrell);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.NotAuthorized.selector, ostrell));
        passport.acceptTransfer(asset);
        vm.prank(other);
        passport.acceptTransfer(asset);
        assertEq(passport.holderOf(asset), other);
    }

    // ---------- E3: no zero address, no self ----------

    function test_E3_zero_address_and_current_holder_rejected() public {
        vm.prank(halvern);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.InvalidWallet.selector, address(0)));
        passport.proposeTransfer(asset, address(0));
        vm.prank(halvern);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.InvalidWallet.selector, halvern));
        passport.proposeTransfer(asset, halvern);
    }

    // ---------- E4: members can't become holder ----------

    function test_E4_member_or_invited_wallet_cannot_be_proposed() public {
        vm.prank(halvern);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.AlreadyMember.selector, pellam));
        passport.proposeTransfer(asset, pellam);
        vm.prank(halvern);
        passport.inviteRole(asset, other, AssetPassport.Role.OmProvider, "Other O&M"); // pending only
        vm.prank(halvern);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.AlreadyMember.selector, other));
        passport.proposeTransfer(asset, other);
    }

    function test_E4_rechecked_at_acceptance() public {
        propose(ostrell);
        vm.prank(halvern); // invited after being proposed
        passport.inviteRole(asset, ostrell, AssetPassport.Role.AssetManager, "Ostrell Capital");
        vm.prank(ostrell);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.AlreadyMember.selector, ostrell));
        passport.acceptTransfer(asset);
        vm.prank(halvern);
        passport.withdrawInvitation(asset, ostrell);
        vm.prank(ostrell);
        passport.acceptTransfer(asset); // allowed once the invitation is gone
        assertEq(passport.holderOf(asset), ostrell);
    }

    function test_E4_revoked_member_can_then_become_holder() public {
        vm.prank(halvern);
        passport.revokeRole(asset, pellam);
        transferTo(pellam);
        assertEq(passport.holderOf(asset), pellam);
    }

    // ---------- E5: previous holder loses every power ----------

    function test_E5_previous_holder_loses_all_powers() public {
        transferTo(ostrell);
        vm.startPrank(halvern);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.NotAuthorized.selector, halvern));
        passport.inviteRole(asset, other, AssetPassport.Role.OmProvider, "Other O&M");
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.NotAuthorized.selector, halvern));
        passport.revokeRole(asset, brennick);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.NotAuthorized.selector, halvern));
        passport.addUnit(asset, unit());
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.NotAuthorized.selector, halvern));
        passport.proposeTransfer(asset, other);
        vm.stopPrank();
        AssetPassport.EntryInput memory e;
        e.category = 5; e.eventDate = MAY_2024; e.headline = "Too late";
        vm.prank(halvern);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.NotAuthorized.selector, halvern));
        passport.submitEntry(asset, e);
    }

    function test_E5_new_holder_has_every_power() public {
        transferTo(ostrell);
        holderEntry(ostrell, "Insurance policy renewed");
        vm.prank(ostrell);
        passport.addUnit(asset, unit());
        vm.prank(ostrell);
        passport.revokeRole(asset, pellam);
        assertEq(passport.unitCount(asset), 1);
    }

    // ---------- E6: members stay active ----------

    function test_E6_members_stay_active_until_new_holder_revokes() public {
        transferTo(ostrell);
        (, AssetPassport.Status s,) = passport.roleOf(asset, brennick);
        assertEq(uint8(s), uint8(AssetPassport.Status.Active));
        omEntry(); // brennick can still submit
        vm.prank(ostrell);
        passport.revokeRole(asset, brennick);
        (, s,) = passport.roleOf(asset, brennick);
        assertEq(uint8(s), uint8(AssetPassport.Status.None));
    }

    // ---------- E7: new holder confirms what was pending ----------

    function test_E7_new_holder_confirms_entry_pending_at_transfer() public {
        uint256 id = omEntry();
        transferTo(ostrell);
        vm.prank(halvern); // the previous holder can no longer confirm it
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.NotAuthorized.selector, halvern));
        passport.confirmEntry(asset, id, H_CABLE);
        vm.prank(ostrell);
        passport.confirmEntry(asset, id, H_CABLE);
        assertEq(passport.getEntry(asset, id).confirmer, ostrell);
    }

    function test_E7_new_holders_asset_manager_confirms_om_entry() public {
        uint256 id = omEntry();
        transferTo(ostrell);
        vm.prank(pellam); // still active (E6), so it can confirm O&M entries
        passport.confirmEntry(asset, id, H_CABLE);
        assertEq(passport.getEntry(asset, id).confirmer, pellam);
    }

    function test_E7_new_holder_confirms_equipment_proposal_pending_at_transfer() public {
        vm.prank(pellam);
        (, uint256 pid) = passport.addUnit(asset, unit());
        transferTo(ostrell);
        vm.prank(halvern);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.NotAuthorized.selector, halvern));
        passport.confirmProposal(asset, pid);
        vm.prank(ostrell);
        passport.confirmProposal(asset, pid);
        assertEq(passport.unitCount(asset), 1);
    }

    // ---------- E8: history untouched ----------

    function test_E8_earlier_entries_keep_their_authors() public {
        uint256 h = holderEntry(halvern, "Warranty claim opened");
        uint256 o = omEntry();
        transferTo(ostrell);
        AssetPassport.Entry memory eh = passport.getEntry(asset, h);
        assertEq(eh.author, halvern);
        assertEq(eh.confirmer, halvern);
        assertEq(uint8(eh.writer), uint8(AssetPassport.Writer.Holder));
        assertEq(passport.getEntry(asset, o).author, brennick);
        assertFalse(passport.getEntry(asset, o).confirmed); // still pending: the record shows it
    }

    function test_E8_identity_unchanged_by_transfer() public {
        transferTo(ostrell);
        (AssetPassport.Identity memory id,) = passport.getAsset(asset);
        assertEq(id.name, "Verrow Solar");
        assertEq(id.capacityKwAc, 10_000);
    }

    // ---------- E9: events ----------

    function test_E9_events_for_proposed_cancelled_and_transferred() public {
        vm.expectEmit(true, true, true, true, address(passport));
        emit AssetPassport.TransferProposed(asset, halvern, ostrell);
        propose(ostrell);
        vm.expectEmit(true, true, true, true, address(passport));
        emit AssetPassport.TransferCancelled(asset, halvern, ostrell);
        vm.prank(halvern);
        passport.cancelTransfer(asset);
        propose(ostrell);
        vm.expectEmit(true, true, true, true, address(passport));
        emit AssetPassport.ControlTransferred(asset, halvern, ostrell);
        vm.prank(ostrell);
        passport.acceptTransfer(asset);
    }

    function test_E9_replacing_a_proposal_emits_only_a_new_proposal() public {
        propose(ostrell);
        vm.recordLogs();
        propose(other);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].topics[0], AssetPassport.TransferProposed.selector);
    }

    // ---------- E10: reading ----------

    function test_E10_pending_holder_readable_and_cleared_after_acceptance() public {
        assertEq(passport.pendingHolderOf(asset), address(0));
        propose(ostrell);
        vm.prank(stranger);
        assertEq(passport.pendingHolderOf(asset), ostrell);
        vm.prank(ostrell);
        passport.acceptTransfer(asset);
        assertEq(passport.pendingHolderOf(asset), address(0)); // cleared
        vm.prank(ostrell); // and cannot be accepted again
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.NotAuthorized.selector, ostrell));
        passport.acceptTransfer(asset);
    }

    function test_E10_unknown_asset_rejected() public {
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.UnknownAsset.selector, 99));
        passport.pendingHolderOf(99);
        vm.prank(halvern);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.UnknownAsset.selector, 99));
        passport.proposeTransfer(99, ostrell);
    }
}
