// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test, Vm} from "forge-std/src/Test.sol";
import {AssetPassport} from "../contracts/AssetPassport.sol";

/// Stage 1 part C: roles, invitations and revocation. Each rule (C1-C10) tested both
/// ways; C11 is covered by AssetPassport.interface.test.ts.
contract AssetPassportPartCTest is Test {
    AssetPassport passport;
    uint256 asset;
    address holder = makeAddr("Halvern Capital");
    address pellam = makeAddr("Pellam Asset Services");
    address brennick = makeAddr("Brennick O&M");
    address dalbeck = makeAddr("Dalbeck Solar Services");
    address stranger = makeAddr("Stranger");

    AssetPassport.Role constant AM = AssetPassport.Role.AssetManager;
    AssetPassport.Role constant OM = AssetPassport.Role.OmProvider;
    AssetPassport.Role constant NONE = AssetPassport.Role.None;

    function setUp() public {
        passport = new AssetPassport();
        AssetPassport.Identity memory id;
        id.name = "Verrow Solar"; id.solar = true; id.state = "California";
        id.county = "Fresno County"; id.capacityKwAc = 10_000;
        vm.prank(holder);
        asset = passport.registerAsset(id);
    }

    // helpers
    function invite(address by, address wallet, AssetPassport.Role role, string memory co) internal {
        vm.prank(by);
        passport.inviteRole(asset, wallet, role, co);
    }
    function accept(address wallet) internal {
        vm.prank(wallet);
        passport.acceptRole(asset);
    }
    function status(address wallet) internal view returns (AssetPassport.Status s) {
        (, s,) = passport.roleOf(asset, wallet);
    }
    function currentRole(address wallet) internal view returns (AssetPassport.Role r) {
        (r,,) = passport.roleOf(asset, wallet);
    }
    function activeManager() internal {
        invite(holder, pellam, AM, "Pellam Asset Services");
        accept(pellam);
    }

    // ---------- C1: two roles; None is not a role ----------

    function test_C1_both_roles_can_be_held() public {
        invite(holder, pellam, AM, "Pellam Asset Services");
        invite(holder, brennick, OM, "Brennick O&M");
        accept(pellam); accept(brennick);
        assertEq(uint8(currentRole(pellam)), uint8(AM));
        assertEq(uint8(currentRole(brennick)), uint8(OM));
    }

    function test_C1_role_none_cannot_be_invited() public {
        vm.prank(holder);
        vm.expectRevert(AssetPassport.InvalidRole.selector);
        passport.inviteRole(asset, pellam, NONE, "Pellam Asset Services");
    }

    // ---------- C2: who may invite, withdraw and revoke ----------

    function test_C2_holder_manages_both_roles() public {
        invite(holder, pellam, AM, "Pellam Asset Services");
        invite(holder, brennick, OM, "Brennick O&M");
        accept(pellam); accept(brennick);
        vm.startPrank(holder);
        passport.revokeRole(asset, pellam);
        passport.revokeRole(asset, brennick);
        vm.stopPrank();
        assertEq(uint8(status(pellam)), uint8(AssetPassport.Status.None));
        assertEq(uint8(status(brennick)), uint8(AssetPassport.Status.None));
    }

    function test_C2_asset_manager_manages_om_providers() public {
        activeManager();
        invite(pellam, brennick, OM, "Brennick O&M");
        accept(brennick);
        vm.prank(pellam);
        passport.revokeRole(asset, brennick);
        invite(pellam, dalbeck, OM, "Dalbeck Solar Services");
        vm.prank(pellam);
        passport.withdrawInvitation(asset, dalbeck);
        assertEq(uint8(status(brennick)), uint8(AssetPassport.Status.None));
        assertEq(uint8(status(dalbeck)), uint8(AssetPassport.Status.None));
    }

    function test_C2_asset_manager_cannot_invite_or_revoke_asset_managers() public {
        activeManager();
        vm.prank(pellam);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.NotAuthorized.selector, pellam));
        passport.inviteRole(asset, stranger, AM, "Another Manager");
        address quenby = makeAddr("Quenby Energy Management");
        invite(holder, quenby, AM, "Quenby Energy Management");
        accept(quenby);
        vm.prank(pellam);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.NotAuthorized.selector, pellam));
        passport.revokeRole(asset, quenby);
    }

    function test_C2_invited_but_not_yet_active_manager_has_no_powers() public {
        invite(holder, pellam, AM, "Pellam Asset Services"); // not accepted
        vm.prank(pellam);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.NotAuthorized.selector, pellam));
        passport.inviteRole(asset, brennick, OM, "Brennick O&M");
    }

    function test_C2_om_provider_and_strangers_have_no_powers() public {
        invite(holder, brennick, OM, "Brennick O&M");
        accept(brennick);
        vm.prank(brennick);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.NotAuthorized.selector, brennick));
        passport.inviteRole(asset, dalbeck, OM, "Dalbeck Solar Services");
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.NotAuthorized.selector, stranger));
        passport.revokeRole(asset, brennick);
        invite(holder, dalbeck, OM, "Dalbeck Solar Services");
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.NotAuthorized.selector, stranger));
        passport.withdrawInvitation(asset, dalbeck);
    }

    function test_C2_asset_manager_can_withdraw_holders_om_invitation() public {
        activeManager();
        invite(holder, brennick, OM, "Brennick O&M");
        vm.prank(pellam);
        passport.withdrawInvitation(asset, brennick);
        assertEq(uint8(status(brennick)), uint8(AssetPassport.Status.None));
    }

    // ---------- C3: invitation, then acceptance by that wallet only ----------

    function test_C3_role_starts_only_on_acceptance() public {
        invite(holder, brennick, OM, "Brennick O&M");
        assertEq(uint8(status(brennick)), uint8(AssetPassport.Status.Invited));
        accept(brennick);
        assertEq(uint8(status(brennick)), uint8(AssetPassport.Status.Active));
    }

    function test_C3_other_wallets_cannot_accept_someone_elses_invitation() public {
        invite(holder, brennick, OM, "Brennick O&M");
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.NoInvitation.selector, stranger));
        passport.acceptRole(asset);
        assertEq(uint8(status(brennick)), uint8(AssetPassport.Status.Invited));
    }

    function test_C3_cannot_accept_twice_or_after_withdrawal() public {
        invite(holder, brennick, OM, "Brennick O&M");
        accept(brennick);
        vm.prank(brennick);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.NoInvitation.selector, brennick));
        passport.acceptRole(asset);
        invite(holder, dalbeck, OM, "Dalbeck Solar Services");
        vm.prank(holder);
        passport.withdrawInvitation(asset, dalbeck);
        vm.prank(dalbeck);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.NoInvitation.selector, dalbeck));
        passport.acceptRole(asset);
    }

    function test_C3_only_pending_invitations_can_be_withdrawn() public {
        invite(holder, brennick, OM, "Brennick O&M");
        accept(brennick);
        vm.prank(holder);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.NoInvitation.selector, brennick));
        passport.withdrawInvitation(asset, brennick);
    }

    // ---------- C4: company name required, up to 100 bytes ----------

    function test_C4_company_recorded_with_the_role() public {
        invite(holder, brennick, OM, "Brennick O&M");
        accept(brennick);
        (,, string memory company) = passport.roleOf(asset, brennick);
        assertEq(company, "Brennick O&M");
    }

    function test_C4_empty_or_too_long_company_rejected() public {
        vm.prank(holder);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.EmptyField.selector, "company"));
        passport.inviteRole(asset, brennick, OM, "");
        bytes memory long = new bytes(101);
        for (uint256 i = 0; i < 101; i++) long[i] = "a";
        vm.prank(holder);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.TextTooLong.selector, "company"));
        passport.inviteRole(asset, brennick, OM, string(long));
        bytes memory ok = new bytes(100);
        for (uint256 i = 0; i < 100; i++) ok[i] = "a";
        invite(holder, brennick, OM, string(ok));
    }

    // ---------- C5: any number of wallets per role ----------

    function test_C5_several_wallets_can_hold_the_same_role() public {
        invite(holder, brennick, OM, "Brennick O&M");
        invite(holder, dalbeck, OM, "Dalbeck Solar Services");
        accept(brennick); accept(dalbeck);
        assertEq(uint8(status(brennick)), uint8(AssetPassport.Status.Active));
        assertEq(uint8(status(dalbeck)), uint8(AssetPassport.Status.Active));
    }

    // ---------- C6: rejected invitations ----------

    function test_C6_cannot_invite_a_wallet_that_already_has_a_role_or_invitation() public {
        invite(holder, brennick, OM, "Brennick O&M");
        vm.prank(holder);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.AlreadyMember.selector, brennick));
        passport.inviteRole(asset, brennick, AM, "Brennick O&M");
        accept(brennick);
        vm.prank(holder);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.AlreadyMember.selector, brennick));
        passport.inviteRole(asset, brennick, OM, "Brennick O&M");
    }

    function test_C6_cannot_invite_the_holder_or_the_zero_address() public {
        vm.prank(holder);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.InvalidWallet.selector, holder));
        passport.inviteRole(asset, holder, OM, "Halvern Capital");
        vm.prank(holder);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.InvalidWallet.selector, address(0)));
        passport.inviteRole(asset, address(0), OM, "Nobody");
    }

    // ---------- C7: revocation ends rights now; re-invitation allowed ----------

    function test_C7_revoked_manager_loses_powers_immediately() public {
        activeManager();
        vm.prank(holder);
        passport.revokeRole(asset, pellam);
        vm.prank(pellam);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.NotAuthorized.selector, pellam));
        passport.inviteRole(asset, brennick, OM, "Brennick O&M");
    }

    function test_C7_revoked_wallet_can_be_invited_again() public {
        invite(holder, brennick, OM, "Brennick O&M");
        accept(brennick);
        vm.prank(holder);
        passport.revokeRole(asset, brennick);
        invite(holder, brennick, OM, "Brennick O&M");
        accept(brennick);
        assertEq(uint8(status(brennick)), uint8(AssetPassport.Status.Active));
    }

    function test_C7_only_active_members_can_be_revoked() public {
        vm.prank(holder);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.NotActiveMember.selector, brennick));
        passport.revokeRole(asset, brennick);
        invite(holder, brennick, OM, "Brennick O&M"); // pending, not active
        vm.prank(holder);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.NotActiveMember.selector, brennick));
        passport.revokeRole(asset, brennick);
    }

    // ---------- C8: events for each step ----------

    function test_C8_each_step_emits_its_event() public {
        vm.expectEmit(true, true, true, true, address(passport));
        emit AssetPassport.RoleInvited(asset, brennick, OM, "Brennick O&M", holder);
        invite(holder, brennick, OM, "Brennick O&M");

        vm.expectEmit(true, true, false, true, address(passport));
        emit AssetPassport.RoleAccepted(asset, brennick, OM, "Brennick O&M");
        accept(brennick);

        vm.expectEmit(true, true, true, true, address(passport));
        emit AssetPassport.RoleRevoked(asset, brennick, OM, holder);
        vm.prank(holder);
        passport.revokeRole(asset, brennick);

        invite(holder, dalbeck, OM, "Dalbeck Solar Services");
        vm.expectEmit(true, true, true, true, address(passport));
        emit AssetPassport.InvitationWithdrawn(asset, dalbeck, OM, holder);
        vm.prank(holder);
        passport.withdrawInvitation(asset, dalbeck);
    }

    function test_C8_event_records_who_acted() public {
        activeManager();
        vm.recordLogs();
        invite(pellam, brennick, OM, "Brennick O&M");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].topics[3], bytes32(uint256(uint160(pellam)))); // by = asset manager
        assertTrue(logs[0].topics[3] != bytes32(uint256(uint160(holder))));
    }

    // ---------- C9: anyone can read; none for non-members ----------

    function test_C9_anyone_can_read_and_non_members_read_as_none() public {
        invite(holder, brennick, OM, "Brennick O&M");
        accept(brennick);
        vm.prank(stranger);
        (AssetPassport.Role r, AssetPassport.Status s, string memory c) = passport.roleOf(asset, brennick);
        assertEq(uint8(r), uint8(OM));
        assertEq(uint8(s), uint8(AssetPassport.Status.Active));
        assertEq(c, "Brennick O&M");
        (r, s, c) = passport.roleOf(asset, stranger);
        assertEq(uint8(r), uint8(NONE));
        assertEq(uint8(s), uint8(AssetPassport.Status.None));
        assertEq(bytes(c).length, 0);
    }

    // ---------- C10: roles only on registered assets ----------

    function test_C10_unknown_asset_rejected_everywhere() public {
        vm.prank(holder);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.UnknownAsset.selector, 99));
        passport.inviteRole(99, brennick, OM, "Brennick O&M");
        vm.prank(brennick);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.UnknownAsset.selector, 99));
        passport.acceptRole(99);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.UnknownAsset.selector, 99));
        passport.roleOf(99, brennick);
    }

    function test_C10_roles_are_per_asset() public {
        AssetPassport.Identity memory id;
        id.name = "Wildrye Solar"; id.solar = true; id.state = "California";
        id.county = "Fresno County"; id.capacityKwAc = 10_000;
        address larkmoor = makeAddr("Larkmoor Capital");
        vm.prank(larkmoor);
        uint256 other = passport.registerAsset(id);
        invite(holder, brennick, OM, "Brennick O&M");
        accept(brennick);
        (, AssetPassport.Status s,) = passport.roleOf(other, brennick);
        assertEq(uint8(s), uint8(AssetPassport.Status.None)); // a role on Verrow is not a role on Wildrye
        vm.prank(holder); // Verrow's holder has no power over Wildrye
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.NotAuthorized.selector, holder));
        passport.inviteRole(other, dalbeck, OM, "Dalbeck Solar Services");
    }
}
