// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test, Vm} from "forge-std/src/Test.sol";
import {AssetPassport} from "../contracts/AssetPassport.sol";

/// Stage 1 part A: assets and identity. Each rule (A1-A9) is tested both ways:
/// what it allows, and what it rejects.
contract AssetPassportPartATest is Test {
    AssetPassport passport;
    address larkmoor = makeAddr("Larkmoor Capital");
    address halvern = makeAddr("Halvern Capital");

    function setUp() public {
        passport = new AssetPassport();
    }

    function wildrye() internal pure returns (AssetPassport.Identity memory id) {
        id.name = "Wildrye Solar";
        id.solar = true;
        id.battery = false;
        id.state = "California";
        id.county = "Fresno County";
        id.municipality = "[Municipality A]";
        id.capacityKwAc = 10_000;
        id.epc = "Kestrand Builders";
        id.spv = "Wildrye Solar LLC";
        id.legalAddress = "100 Example Avenue, Suite 210, Fresno, CA";
    }

    function text(uint256 n, bytes1 ch) internal pure returns (string memory) {
        bytes memory b = new bytes(n);
        for (uint256 i = 0; i < n; i++) b[i] = ch;
        return string(b);
    }

    function accented(uint256 count) internal pure returns (string memory s) {
        // "é" is 2 bytes in UTF-8
        for (uint256 i = 0; i < count; i++) s = string.concat(s, unicode"é");
    }

    // ---------- A1: anyone can register; the registrant becomes the holder ----------

    function test_A1_any_wallet_can_register_and_becomes_holder() public {
        vm.prank(larkmoor);
        uint256 a = passport.registerAsset(wildrye());
        vm.prank(halvern);
        uint256 b = passport.registerAsset(wildrye());
        assertEq(passport.holderOf(a), larkmoor);
        assertEq(passport.holderOf(b), halvern);
    }

    function test_A1_holder_is_the_caller_not_anyone_else() public {
        vm.prank(larkmoor);
        uint256 a = passport.registerAsset(wildrye());
        assertTrue(passport.holderOf(a) != halvern);
        assertTrue(passport.holderOf(a) != address(this));
        assertTrue(passport.holderOf(a) != address(0));
    }

    // ---------- A2: numbered 1, 2, 3... in order; never 0 ----------

    function test_A2_numbers_start_at_1_and_run_in_order() public {
        assertEq(passport.assetCount(), 0);
        assertEq(passport.registerAsset(wildrye()), 1);
        assertEq(passport.registerAsset(wildrye()), 2);
        assertEq(passport.registerAsset(wildrye()), 3);
        assertEq(passport.assetCount(), 3);
    }

    function test_A2_asset_number_0_never_exists() public {
        passport.registerAsset(wildrye());
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.UnknownAsset.selector, 0));
        passport.getAsset(0);
    }

    // ---------- A3: required fields can't be empty; optional ones can ----------

    function test_A3_empty_name_rejected() public {
        AssetPassport.Identity memory id = wildrye();
        id.name = "";
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.EmptyField.selector, "name"));
        passport.registerAsset(id);
    }

    function test_A3_empty_state_rejected() public {
        AssetPassport.Identity memory id = wildrye();
        id.state = "";
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.EmptyField.selector, "state"));
        passport.registerAsset(id);
    }

    function test_A3_empty_county_rejected() public {
        AssetPassport.Identity memory id = wildrye();
        id.county = "";
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.EmptyField.selector, "county"));
        passport.registerAsset(id);
    }

    function test_A3_optional_fields_may_be_empty() public {
        AssetPassport.Identity memory id = wildrye();
        id.municipality = "";
        id.epc = "";
        id.spv = "";
        id.legalAddress = "";
        uint256 a = passport.registerAsset(id);
        (AssetPassport.Identity memory stored,) = passport.getAsset(a);
        assertEq(bytes(stored.municipality).length, 0);
        assertEq(bytes(stored.legalAddress).length, 0);
    }

    // ---------- A4: capacity in whole kW, greater than zero ----------

    function test_A4_zero_capacity_rejected() public {
        AssetPassport.Identity memory id = wildrye();
        id.capacityKwAc = 0;
        vm.expectRevert(AssetPassport.ZeroCapacity.selector);
        passport.registerAsset(id);
    }

    function test_A4_capacity_of_1_kw_accepted_and_stored_exactly() public {
        AssetPassport.Identity memory id = wildrye();
        id.capacityKwAc = 1;
        uint256 a = passport.registerAsset(id);
        (AssetPassport.Identity memory stored,) = passport.getAsset(a);
        assertEq(stored.capacityKwAc, 1);
    }

    // ---------- A5: at least one technology ----------

    function test_A5_no_technology_rejected() public {
        AssetPassport.Identity memory id = wildrye();
        id.solar = false;
        id.battery = false;
        vm.expectRevert(AssetPassport.NoTechnology.selector);
        passport.registerAsset(id);
    }

    function test_A5_solar_only_battery_only_and_both_accepted() public {
        AssetPassport.Identity memory id = wildrye();
        id.solar = true; id.battery = false;
        passport.registerAsset(id);
        id.solar = false; id.battery = true;
        passport.registerAsset(id);
        id.solar = true; id.battery = true;
        uint256 c = passport.registerAsset(id);
        (AssetPassport.Identity memory stored,) = passport.getAsset(c);
        assertTrue(stored.solar && stored.battery);
    }

    // ---------- A6: text limited to 100 bytes ----------

    function test_A6_exactly_100_bytes_accepted_in_every_field() public {
        AssetPassport.Identity memory id = wildrye();
        string memory t = text(100, "a");
        id.name = t; id.state = t; id.county = t; id.municipality = t;
        id.epc = t; id.spv = t; id.legalAddress = t;
        passport.registerAsset(id);
    }

    function test_A6_101_bytes_rejected_in_each_field() public {
        string memory t = text(101, "a");
        string[7] memory fields = ["name", "state", "county", "municipality", "epc", "spv", "legalAddress"];
        for (uint256 i = 0; i < 7; i++) {
            AssetPassport.Identity memory id = wildrye();
            if (i == 0) id.name = t;
            if (i == 1) id.state = t;
            if (i == 2) id.county = t;
            if (i == 3) id.municipality = t;
            if (i == 4) id.epc = t;
            if (i == 5) id.spv = t;
            if (i == 6) id.legalAddress = t;
            vm.expectRevert(abi.encodeWithSelector(AssetPassport.TextTooLong.selector, fields[i]));
            passport.registerAsset(id);
        }
    }

    function test_A6_limit_counts_bytes_not_characters() public {
        AssetPassport.Identity memory id = wildrye();
        id.name = accented(50); // 50 characters = 100 bytes: accepted
        passport.registerAsset(id);
        id.name = accented(51); // 51 characters = 102 bytes: rejected
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.TextTooLong.selector, "name"));
        passport.registerAsset(id);
    }

    // ---------- A7: one event with the asset number, holder and every field ----------

    function test_A7_registration_emits_event_with_every_field() public {
        AssetPassport.Identity memory id = wildrye();
        vm.expectEmit(true, true, false, true, address(passport));
        emit AssetPassport.AssetRegistered(1, larkmoor, id);
        vm.prank(larkmoor);
        passport.registerAsset(id);
    }

    function test_A7_event_would_not_match_a_different_holder() public {
        AssetPassport.Identity memory id = wildrye();
        vm.recordLogs();
        vm.prank(larkmoor);
        passport.registerAsset(id);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].topics[1], bytes32(uint256(1)));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(larkmoor))));
        assertTrue(logs[0].topics[2] != bytes32(uint256(uint160(halvern))));
        AssetPassport.Identity memory emitted = abi.decode(logs[0].data, (AssetPassport.Identity));
        assertEq(emitted.legalAddress, id.legalAddress);
        assertEq(emitted.municipality, id.municipality);
        assertEq(emitted.capacityKwAc, id.capacityKwAc);
    }

    // ---------- A8: identity is fixed (checked also by the ABI test) ----------

    function test_A8_identity_unchanged_after_later_registrations() public {
        vm.prank(larkmoor);
        uint256 a = passport.registerAsset(wildrye());
        AssetPassport.Identity memory other = wildrye();
        other.name = "Verrow Solar";
        other.capacityKwAc = 9_999;
        vm.prank(halvern);
        passport.registerAsset(other);
        (AssetPassport.Identity memory stored, address holder) = passport.getAsset(a);
        assertEq(stored.name, "Wildrye Solar");
        assertEq(stored.capacityKwAc, 10_000);
        assertEq(holder, larkmoor);
    }

    // ---------- A9: anyone can read; unknown numbers rejected ----------

    function test_A9_anyone_can_read_identity_and_holder() public {
        vm.prank(larkmoor);
        uint256 a = passport.registerAsset(wildrye());
        vm.prank(halvern); // a different wallet reads it
        (AssetPassport.Identity memory stored, address holder) = passport.getAsset(a);
        assertEq(stored.name, "Wildrye Solar");
        assertEq(stored.county, "Fresno County");
        assertEq(stored.spv, "Wildrye Solar LLC");
        assertEq(holder, larkmoor);
    }

    function test_A9_unknown_asset_number_rejected() public {
        passport.registerAsset(wildrye());
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.UnknownAsset.selector, 2));
        passport.getAsset(2);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.UnknownAsset.selector, 99));
        passport.holderOf(99);
    }
}
