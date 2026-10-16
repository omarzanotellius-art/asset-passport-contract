// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/src/Test.sol";
import {AssetPassport} from "../contracts/AssetPassport.sol";

/// Stage 1 part F: both farms' full stories, 2021-2026, as in the interactive demo
/// (spec v1.5 §5-§8). The clock is moved to each event's real date before it is
/// recorded, so "recorded later" is measured with real dates. On Amoy this is not
/// possible; there the demo-only overlay file supplies simulated recorded dates (D51).
contract AssetPassportStoryTest is Test {
    AssetPassport passport;

    // Wildrye
    address larkmoor = makeAddr("Larkmoor Capital");
    address tavren = makeAddr("Tavren Asset Management");
    address tarrow = makeAddr("Tarrow Field Services");
    // Verrow
    address halvern = makeAddr("Halvern Capital");
    address ostrell = makeAddr("Ostrell Capital");
    address pellam = makeAddr("Pellam Asset Services");
    address quenby = makeAddr("Quenby Energy Management");
    address brennick = makeAddr("Brennick O&M");
    address dalbeck = makeAddr("Dalbeck Solar Services");

    AssetPassport.Role constant AM = AssetPassport.Role.AssetManager;
    AssetPassport.Role constant OM = AssetPassport.Role.OmProvider;

    // categories (format document)
    uint8 constant COMMISSIONING = 1;
    uint8 constant SCHEDULED = 2;
    uint8 constant UNSCHEDULED = 3;
    uint8 constant REPLACEMENT = 4;
    uint8 constant WARRANTY_CLAIM = 5;
    uint8 constant WARRANTY_DISPUTE = 6;
    uint8 constant PRODUCTION = 9;
    uint8 constant CONTRACT_CHANGE = 10;
    uint8 constant INSURANCE_POLICY = 14;
    uint16 constant INVERTERS = 1;

    // Verrow story: key numbers kept as fields, not locals (Solidity "stack too deep" limit)
    uint256 v;
    uint256 inv2;
    uint256 inv2b;
    uint256 claim;
    uint256 dispute;
    uint256 cablePending;
    uint256 late;

    // ---------------------------------------------------------------- helpers

    /// Unix time of the 1st of a month (UTC), from the civil calendar.
    function ym(uint256 y, uint256 m) internal pure returns (uint64) {
        if (m <= 2) y -= 1;
        uint256 era = y / 400;
        uint256 yoe = y - era * 400;
        uint256 mp = m > 2 ? m - 3 : m + 9;
        uint256 doy = (153 * mp + 2) / 5;
        uint256 doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
        uint256 days_ = era * 146097 + doe - 719468;
        return uint64(days_ * 1 days);
    }

    function setDate(uint256 y, uint256 m) internal {
        vm.warp(ym(y, m) + 12 hours);
    }

    function register(address holder, string memory name, string memory epc) internal returns (uint256 a) {
        AssetPassport.Identity memory id;
        id.name = name; id.solar = true; id.state = "California"; id.county = "Fresno County";
        id.municipality = "[Municipality]"; id.capacityKwAc = 10_000; id.epc = epc;
        id.spv = string.concat(name, " LLC");
        vm.prank(holder);
        a = passport.registerAsset(id);
    }

    function join(uint256 a, address by, address w, AssetPassport.Role r, string memory company) internal {
        vm.prank(by);
        passport.inviteRole(a, w, r, company);
        vm.prank(w);
        passport.acceptRole(a);
    }

    function inverter(string memory name, uint64 inService, uint64 warrantyEnd)
        internal pure returns (AssetPassport.UnitInput memory u)
    {
        u.name = name; u.system = INVERTERS; u.oem = "Brindle Inverter Systems"; u.model = "CI-3400";
        u.rating = "3,400 kWac"; u.quantity = 1; u.inService = inService;
        u.warrantyStart = inService; u.warrantyEnd = warrantyEnd;
    }

    /// Holder entry: text at submission, confirmed at once.
    function holderEntry(uint256 a, address h, uint8 cat, uint64 eventDate, string memory headline, string memory equip, uint256 link)
        internal returns (uint256 id)
    {
        AssetPassport.EntryInput memory e;
        e.category = cat; e.eventDate = eventDate; e.headline = headline; e.equipmentRef = equip; e.link = link;
        vm.prank(h);
        id = passport.submitEntry(a, e);
    }

    /// O&M entry: fingerprint only; confirmed later (or never) by holder or asset manager.
    function omEntry(uint256 a, address w, uint8 cat, uint64 eventDate, string memory headline, string memory equip)
        internal returns (uint256 id)
    {
        AssetPassport.EntryInput memory e;
        e.category = cat; e.eventDate = eventDate; e.headlineFingerprint = sha256(bytes(headline)); e.equipmentRef = equip;
        vm.prank(w);
        id = passport.submitEntry(a, e);
    }

    function confirm(uint256 a, address by, uint256 id, string memory headline) internal {
        vm.prank(by);
        passport.confirmEntry(a, id, headline);
    }

    function visit(uint256 a, address om, address confirmer, uint256 y) internal {
        setDate(y, 3);
        uint256 id = omEntry(a, om, SCHEDULED, ym(y, 3), "Annual visit", "");
        confirm(a, confirmer, id, "Annual visit");
    }

    function production(uint256 a, address h, uint256 y, string memory headline) internal {
        setDate(y + 1, 1); // reported the following January
        holderEntry(a, h, PRODUCTION, ym(y + 1, 1) - 1 days, headline, "", 0);
    }

    function setUp() public {
        setDate(2021, 7);
        passport = new AssetPassport();
    }

    // ================================================================ Verrow Solar

    function test_F_verrow_full_story_through_the_sale() public {
        // --- Jul 2021: commissioning, parties, equipment
        setDate(2021, 7);
        v = register(halvern, "Verrow Solar", "Norvale Constructors");
        join(v, halvern, pellam, AM, "Pellam Asset Services");
        join(v, halvern, brennick, OM, "Brennick O&M");
        holderEntry(v, halvern, COMMISSIONING, ym(2021, 7), "10 MWac, original, EPC: Norvale Constructors", "", 0);
        vm.startPrank(halvern);
        passport.addUnit(v, inverter("Inverter 1", ym(2021, 7), ym(2026, 7)));
        (, inv2) = passport.addUnit(v, inverter("Inverter 2", ym(2021, 7), ym(2026, 7)));
        passport.addUnit(v, inverter("Inverter 3", ym(2021, 7), ym(2026, 7)));
        passport.extendWarranty(v, 1, ym(2031, 7));
        passport.extendWarranty(v, 3, ym(2031, 7));
        vm.stopPrank();

        // --- 2022: inverter 2 trips, claim opened, cable section C first repaired
        visit(v, brennick, pellam, 2022);
        setDate(2022, 4);
        uint256 e = omEntry(v, brennick, UNSCHEDULED, ym(2022, 4), "Control board replaced after a trip", "Inverter 2");
        confirm(v, halvern, e, "Control board replaced after a trip");
        setDate(2022, 9);
        claim = holderEntry(v, halvern, WARRANTY_CLAIM, ym(2022, 9), "Warranty claim opened", "Inverter 2", 0);
        setDate(2022, 10);
        e = omEntry(v, brennick, UNSCHEDULED, ym(2022, 10), "Temporary repair", "Cable section C");
        confirm(v, halvern, e, "Temporary repair");
        production(v, halvern, 2021, "2021 (from Jul): 12,900 MWh");
        production(v, halvern, 2022, "2022: 24,100 MWh");

        // --- 2023: cable again; inverter 2 replaced (entry by O&M, equipment by holder: D46/B6 option A)
        visit(v, brennick, pellam, 2023);
        setDate(2023, 6);
        e = omEntry(v, brennick, UNSCHEDULED, ym(2023, 6), "Insulation repaired", "Cable section C");
        confirm(v, halvern, e, "Insulation repaired");
        setDate(2023, 9);
        e = omEntry(v, brennick, REPLACEMENT, ym(2023, 9), "Replaced with a new unit", "Inverter 2");
        confirm(v, halvern, e, "Replaced with a new unit");
        vm.prank(halvern);
        (, inv2b) = passport.replaceUnit(v, inv2, inverter("Inverter 2", ym(2023, 9), ym(2028, 9)), ym(2023, 9));
        vm.prank(halvern);
        passport.extendWarranty(v, inv2b, ym(2033, 9));
        production(v, halvern, 2023, "2023: 22,500 MWh");

        // --- 2024: dispute; NO scheduled visit (D46); cable entry never confirmed; provider replaced
        setDate(2024, 3);
        dispute = holderEntry(v, halvern, WARRANTY_DISPUTE, ym(2024, 3), "Dispute opened over the Sep 2022 claim", "Inverter 2", claim);
        setDate(2024, 5);
        cablePending = omEntry(v, brennick, UNSCHEDULED, ym(2024, 5), "Further work on cable section C", "Cable section C");
        setDate(2024, 6);
        vm.prank(halvern);
        passport.revokeRole(v, brennick);
        join(v, halvern, dalbeck, OM, "Dalbeck Solar Services");

        // --- Nov 2024: the 2022 second call-out recorded only now, before the sale
        setDate(2024, 11);
        late = holderEntry(v, halvern, UNSCHEDULED, ym(2022, 8), "Corrective work, second call-out", "Inverter 2", 0);
        production(v, halvern, 2024, "2024: 25,800 MWh");

        // --- Feb 2025: the sale. Two steps; asset manager replaced by the new holder.
        setDate(2025, 2);
        vm.prank(halvern);
        passport.proposeTransfer(v, ostrell);
        vm.prank(ostrell);
        passport.acceptTransfer(v);
        vm.prank(ostrell);
        passport.revokeRole(v, pellam);
        join(v, ostrell, quenby, AM, "Quenby Energy Management");

        // --- 2025-2026 under the new holder: cable section C again
        visit(v, dalbeck, quenby, 2025);
        setDate(2025, 8);
        e = omEntry(v, dalbeck, UNSCHEDULED, ym(2025, 8), "Insulation work", "Cable section C");
        confirm(v, ostrell, e, "Insulation work");
        production(v, ostrell, 2025, "2025: 25,500 MWh");
        setDate(2026, 3);
        holderEntry(v, ostrell, INSURANCE_POLICY, ym(2026, 3), "Property damage (all risk), Ashcomb Insurance", "", 0);
        holderEntry(v, ostrell, INSURANCE_POLICY, ym(2026, 3), "Business interruption, Ashcomb Insurance", "", 0);
        holderEntry(v, ostrell, INSURANCE_POLICY, ym(2026, 3), "General liability, Ashcomb Insurance", "", 0);
        visit(v, dalbeck, quenby, 2026);
        setDate(2026, 10);
        holderEntry(v, ostrell, PRODUCTION, ym(2026, 10) - 1 days, "2026 (Jan-Sep): 21,400 MWh", "", 0);

        checkVerrowInOct2026();
    }

    /// What Verrow's passport shows in Oct 2026.
    function checkVerrowInOct2026() internal {

        // control: Ostrell holds; nothing pending; Halvern has no powers left
        assertEq(passport.holderOf(v), ostrell);
        assertEq(passport.pendingHolderOf(v), address(0));
        AssetPassport.EntryInput memory tooLate;
        tooLate.category = UNSCHEDULED; tooLate.eventDate = ym(2025, 1); tooLate.headline = "Too late";
        vm.prank(halvern);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.NotAuthorized.selector, halvern));
        passport.submitEntry(v, tooLate);

        // parties: Brennick and Pellam gone, Dalbeck and Quenby active
        (, AssetPassport.Status s,) = passport.roleOf(v, brennick);
        assertEq(uint8(s), uint8(AssetPassport.Status.None));
        (, s,) = passport.roleOf(v, pellam);
        assertEq(uint8(s), uint8(AssetPassport.Status.None));
        (, s,) = passport.roleOf(v, dalbeck);
        assertEq(uint8(s), uint8(AssetPassport.Status.Active));
        (, s,) = passport.roleOf(v, quenby);
        assertEq(uint8(s), uint8(AssetPassport.Status.Active));

        // the entry Halvern never confirmed: still pending through the sale, wording hidden,
        // still labelled with Brennick's role and company
        AssetPassport.Entry memory p = passport.getEntry(v, cablePending);
        assertFalse(p.confirmed);
        assertEq(bytes(p.headline).length, 0);
        assertEq(p.authorCompany, "Brennick O&M");
        assertEq(p.equipmentRef, "Cable section C");

        // recorded later: the Aug 2022 work recorded in Nov 2024, by the previous holder
        AssetPassport.Entry memory l = passport.getEntry(v, late);
        assertEq(l.eventDate, ym(2022, 8));
        assertGt(l.recordedAt - l.eventDate, 800 days);
        assertEq(l.author, halvern);

        // the dispute is linked to its claim, with no resolution entry
        assertEq(passport.getEntry(v, dispute).link, claim);

        checkVerrowPatterns();

        // equipment: inverter 2 replaced in Sep 2023; old unit kept; new unit's own warranty
        (AssetPassport.Unit memory oldInv,) = passport.getUnit(v, inv2);
        (AssetPassport.Unit memory newInv, uint64 newEnd) = passport.getUnit(v, inv2b);
        assertEq(oldInv.replacedBy, inv2b);
        assertEq(oldInv.replacedAt, ym(2023, 9));
        assertEq(newInv.replaces, inv2);
        assertEq(newEnd, ym(2033, 9));
        (, uint64 inv1End) = passport.getUnit(v, 1);
        assertEq(inv1End, ym(2031, 7));
        assertEq(passport.unitCount(v), 4);

        // identity untouched by the sale
        (AssetPassport.Identity memory id,) = passport.getAsset(v);
        assertEq(id.name, "Verrow Solar");
        assertEq(id.epc, "Norvale Constructors");
    }

    /// Work returning to the same places, with no labels needed: cable section C 4 times
    /// (one still pending), inverter 2 five times; and no scheduled visit in 2024.
    function checkVerrowPatterns() internal view {
        uint256 cable;
        uint256 inv;
        bool visit2024;
        uint256 n = passport.entryCount(v);
        for (uint256 i = 1; i <= n; i++) {
            AssetPassport.Entry memory x = passport.getEntry(v, i);
            if (keccak256(bytes(x.equipmentRef)) == keccak256("Cable section C")) cable++;
            if (keccak256(bytes(x.equipmentRef)) == keccak256("Inverter 2")) inv++;
            if (x.category == SCHEDULED && x.eventDate >= ym(2024, 1) && x.eventDate < ym(2025, 1)) visit2024 = true;
        }
        assertEq(cable, 4);
        assertEq(inv, 5); // control board, claim, replacement, dispute, late second call-out
        assertFalse(visit2024);
    }

    // ================================================================ Wildrye Solar

    function test_F_wildrye_full_story_one_holder_throughout() public {
        setDate(2021, 7);
        uint256 w = register(larkmoor, "Wildrye Solar", "Kestrand Builders");
        join(w, larkmoor, tavren, AM, "Tavren Asset Management");
        join(w, larkmoor, tarrow, OM, "Tarrow Field Services");
        holderEntry(w, larkmoor, COMMISSIONING, ym(2021, 7), "10 MWac, original, EPC: Kestrand Builders", "", 0);
        vm.startPrank(larkmoor);
        for (uint256 i = 1; i <= 3; i++) {
            passport.addUnit(w, inverter(string.concat("Inverter ", vm.toString(i)), ym(2021, 7), ym(2026, 7)));
            passport.extendWarranty(w, i, ym(2031, 7));
        }
        vm.stopPrank();

        visit(w, tarrow, tavren, 2022);
        production(w, larkmoor, 2021, "2021 (from Jul): 12,900 MWh");
        production(w, larkmoor, 2022, "2022: 26,200 MWh");
        visit(w, tarrow, tavren, 2023);
        setDate(2023, 6);
        uint256 e = omEntry(w, tarrow, UNSCHEDULED, ym(2023, 6), "Tracker motor replaced", "Trackers");
        confirm(w, tavren, e, "Tracker motor replaced"); // corrective work, not a replacement (D46)
        production(w, larkmoor, 2023, "2023: 25,000 MWh");
        visit(w, tarrow, tavren, 2024);
        setDate(2024, 7);
        holderEntry(w, larkmoor, CONTRACT_CHANGE, ym(2024, 7), "O&M contract renewed, same provider", "", 0);
        production(w, larkmoor, 2024, "2024: 26,100 MWh");
        visit(w, tarrow, tavren, 2025);
        production(w, larkmoor, 2025, "2025: 25,800 MWh");
        visit(w, tarrow, tavren, 2026);
        setDate(2026, 7);
        holderEntry(w, larkmoor, INSURANCE_POLICY, ym(2026, 7), "Property damage (all risk), Granmoor Insurance", "", 0);
        holderEntry(w, larkmoor, INSURANCE_POLICY, ym(2026, 7), "Business interruption, Granmoor Insurance", "", 0);
        holderEntry(w, larkmoor, INSURANCE_POLICY, ym(2026, 7), "General liability, Granmoor Insurance", "", 0);
        setDate(2026, 10);
        holderEntry(w, larkmoor, PRODUCTION, ym(2026, 10) - 1 days, "2026 (Jan-Sep): 21,500 MWh", "", 0);

        // one holder, nothing pending anywhere, no replacements, nothing recorded late
        assertEq(passport.holderOf(w), larkmoor);
        assertEq(passport.pendingHolderOf(w), address(0));
        uint256 n = passport.entryCount(w);
        uint256 visits;
        for (uint256 i = 1; i <= n; i++) {
            AssetPassport.Entry memory x = passport.getEntry(w, i);
            assertTrue(x.confirmed);
            assertLt(x.recordedAt - x.eventDate, 30 days);
            assertTrue(x.category != REPLACEMENT);
            if (x.category == SCHEDULED) visits++;
        }
        assertEq(visits, 5); // every year 2022-2026
        for (uint256 i = 1; i <= 3; i++) {
            (AssetPassport.Unit memory u, uint64 end) = passport.getUnit(w, i);
            assertEq(u.replacedAt, 0);
            assertEq(end, ym(2031, 7));
        }
    }

    // ================================================================ side by side

    function test_F_both_farms_in_one_contract_stay_separate() public {
        setDate(2021, 7);
        uint256 wildryeId = register(larkmoor, "Wildrye Solar", "Kestrand Builders");
        uint256 verrowId = register(halvern, "Verrow Solar", "Norvale Constructors");
        assertEq(wildryeId, 1); // AP-0001
        assertEq(verrowId, 2); // AP-0002
        join(wildryeId, larkmoor, tarrow, OM, "Tarrow Field Services");
        // Tarrow has no role on Verrow, and Verrow's holder has no power over Wildrye
        uint64 when = ym(2021, 7);
        AssetPassport.EntryInput memory x;
        x.category = SCHEDULED; x.eventDate = when; x.headlineFingerprint = sha256("Annual visit");
        vm.prank(tarrow);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.NotAuthorized.selector, tarrow));
        passport.submitEntry(verrowId, x);
        vm.prank(halvern);
        vm.expectRevert(abi.encodeWithSelector(AssetPassport.NotAuthorized.selector, halvern));
        passport.revokeRole(wildryeId, tarrow);
    }
}
