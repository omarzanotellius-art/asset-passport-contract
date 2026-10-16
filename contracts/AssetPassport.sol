// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

/// @title Asset passport (learning project, testnet only)
/// @notice A record of what a renewable energy asset is and what has happened to it.
///         Stage 1 part A: assets and identity (rules A1-A9).
///         Stage 1 part C: roles, invitations and revocation (rules C1-C11).
///         Stage 1 part B: equipment list and warranties (rules B1-B12).
contract AssetPassport {
    /// A6: every text field is limited to 100 bytes.
    uint256 public constant MAX_TEXT_BYTES = 100;

    /// Identity of an asset, fixed at registration (A8).
    struct Identity {
        string name;            // required (A3)
        bool solar;             // A5: at least one of solar / battery
        bool battery;
        string state;           // required (A3)
        string county;          // required (A3)
        string municipality;    // optional; stored, not displayed by the viewer (D50)
        uint32 capacityKwAc;    // A4: whole kW, greater than zero
        string epc;             // optional
        string spv;             // optional
        string legalAddress;    // optional
    }

    struct Asset {
        Identity identity;
        address holder;         // A1: the registering wallet
    }

    /// C1: the two roles. The holder is not a role (it is the asset's holder, part A).
    enum Role { None, AssetManager, OmProvider }

    /// C3: a wallet is either not a member, invited (pending), or active.
    enum Status { None, Invited, Active }

    struct Membership {
        Role role;
        Status status;
        string company; // C4
    }

    /// B2: a unit as entered. Warranty start and end both 0 = no warranty (B7).
    struct UnitInput {
        string name;            // required
        uint16 system;          // B4: number defined in the format document; 0 rejected
        string oem;             // required
        string model;           // optional
        string rating;          // optional, text such as "3,400 kWac"
        uint32 quantity;        // > 0
        uint64 inService;       // B5: timestamp, not in the future
        bool isPart;            // sub-component, e.g. tracker drives
        uint64 warrantyStart;
        uint64 warrantyEnd;
    }

    /// B6, B8, B10: a unit as stored. Only replacedAt/replacedBy change, once.
    struct Unit {
        UnitInput spec;
        uint64 replacedAt;      // 0 = in service
        uint256 replacedBy;     // new unit number, 0 if none
        uint256 replaces;       // old unit number, 0 if none
    }

    /// B1: what an asset manager can propose.
    enum ProposalKind { None, AddUnit, ReplaceUnit, ExtendWarranty }
    enum ProposalStatus { None, Pending, Confirmed, Withdrawn }

    struct Proposal {
        ProposalKind kind;
        ProposalStatus status;
        address proposer;
        bytes payload;          // the change, applied unchanged on confirmation
    }

    /// A2: number of assets registered so far; asset numbers run 1..assetCount.
    uint256 public assetCount;
    mapping(uint256 => Asset) private _assets;
    /// C5: any number of wallets per role; one membership per wallet per asset (C6).
    mapping(uint256 => mapping(address => Membership)) private _members;
    /// B3: units numbered 1..unitCount[assetId] within each asset.
    mapping(uint256 => uint256) public unitCount;
    mapping(uint256 => mapping(uint256 => Unit)) private _units;
    /// B7: appended warranty extensions (each a new end date), per unit.
    mapping(uint256 => mapping(uint256 => uint64[])) private _extensions;
    mapping(uint256 => uint256) public proposalCount;
    mapping(uint256 => mapping(uint256 => Proposal)) private _proposals;

    /// A7: one event carrying the asset number, the holder and every identity field.
    event AssetRegistered(uint256 indexed assetId, address indexed holder, Identity identity);

    /// C8: one event per step; the block's timestamp gives the time.
    event RoleInvited(uint256 indexed assetId, address indexed wallet, Role role, string company, address indexed by);
    event InvitationWithdrawn(uint256 indexed assetId, address indexed wallet, Role role, address indexed by);
    event RoleAccepted(uint256 indexed assetId, address indexed wallet, Role role, string company);
    event RoleRevoked(uint256 indexed assetId, address indexed wallet, Role role, address indexed by);

    /// B9: events for every change; `author` is who made the change (the holder,
    /// or the asset manager whose proposal the holder confirmed).
    event UnitAdded(uint256 indexed assetId, uint256 indexed unitId, UnitInput spec, address indexed author);
    event UnitReplaced(uint256 indexed assetId, uint256 indexed oldUnitId, uint256 newUnitId, uint64 replacedAt, address indexed author);
    event WarrantyExtended(uint256 indexed assetId, uint256 indexed unitId, uint64 newEnd, address indexed author);
    event ProposalMade(uint256 indexed assetId, uint256 indexed proposalId, ProposalKind kind, address indexed proposer);
    event ProposalConfirmed(uint256 indexed assetId, uint256 indexed proposalId);
    event ProposalWithdrawn(uint256 indexed assetId, uint256 indexed proposalId);

    error EmptyField(string field);
    error TextTooLong(string field);
    error NoTechnology();
    error ZeroCapacity();
    error UnknownAsset(uint256 assetId);
    error InvalidRole();
    error InvalidWallet(address wallet);
    error AlreadyMember(address wallet);
    error NoInvitation(address wallet);
    error NotActiveMember(address wallet);
    error NotAuthorized(address caller);
    error InvalidSystem();
    error ZeroQuantity();
    error DateInFuture();
    error InvalidWarranty();
    error UnknownUnit(uint256 unitId);
    error AlreadyReplaced(uint256 unitId);
    error SystemMismatch();
    error ReplacementBeforeInService();
    error NoWarranty(uint256 unitId);
    error ExtensionNotLater();
    error UnknownProposal(uint256 proposalId);
    error ProposalNotPending(uint256 proposalId);

    /// A1-A7: register an asset. Anyone may call; the caller becomes the holder.
    function registerAsset(Identity calldata identity) external returns (uint256 assetId) {
        _checkText(identity.name, "name", true);
        _checkText(identity.state, "state", true);
        _checkText(identity.county, "county", true);
        _checkText(identity.municipality, "municipality", false);
        _checkText(identity.epc, "epc", false);
        _checkText(identity.spv, "spv", false);
        _checkText(identity.legalAddress, "legalAddress", false);
        if (!identity.solar && !identity.battery) revert NoTechnology();
        if (identity.capacityKwAc == 0) revert ZeroCapacity();

        assetId = ++assetCount; // A2: first asset is 1
        Asset storage asset = _assets[assetId];
        asset.identity = identity;
        asset.holder = msg.sender;

        emit AssetRegistered(assetId, msg.sender, identity);
    }

    /// A9: anyone can read; unknown asset numbers are rejected rather than returning blanks.
    function getAsset(uint256 assetId) external view returns (Identity memory identity, address holder) {
        Asset storage asset = _existing(assetId);
        return (asset.identity, asset.holder);
    }

    /// A9: the current holder of an asset.
    function holderOf(uint256 assetId) external view returns (address) {
        return _existing(assetId).holder;
    }

    // A8: there is deliberately no function that edits an asset's identity.

    // ---------------------------------------------------------------- part C: roles

    /// C2, C3, C4, C6: invite a wallet to a role. The holder may invite both roles;
    /// an active asset manager may invite O&M providers only.
    function inviteRole(uint256 assetId, address wallet, Role role, string calldata company) external {
        Asset storage asset = _existing(assetId);
        if (role == Role.None) revert InvalidRole();
        if (wallet == address(0) || wallet == asset.holder) revert InvalidWallet(wallet);
        Membership storage m = _members[assetId][wallet];
        if (m.status != Status.None) revert AlreadyMember(wallet);
        _checkText(company, "company", true);
        _requireCanManage(assetId, asset, role);

        m.role = role;
        m.status = Status.Invited;
        m.company = company;
        emit RoleInvited(assetId, wallet, role, company, msg.sender);
    }

    /// C2, C3: withdraw a pending invitation. Same powers as inviting.
    function withdrawInvitation(uint256 assetId, address wallet) external {
        Asset storage asset = _existing(assetId);
        Membership storage m = _members[assetId][wallet];
        if (m.status != Status.Invited) revert NoInvitation(wallet);
        Role role = m.role;
        _requireCanManage(assetId, asset, role);

        delete _members[assetId][wallet];
        emit InvitationWithdrawn(assetId, wallet, role, msg.sender);
    }

    /// C3: only the invited wallet can accept, and only while the invitation is pending.
    function acceptRole(uint256 assetId) external {
        _existing(assetId);
        Membership storage m = _members[assetId][msg.sender];
        if (m.status != Status.Invited) revert NoInvitation(msg.sender);

        m.status = Status.Active;
        emit RoleAccepted(assetId, msg.sender, m.role, m.company);
    }

    /// C2, C7: revoke an active member. Rights end at once; past records stay;
    /// the wallet may be invited again later (a new period).
    function revokeRole(uint256 assetId, address wallet) external {
        Asset storage asset = _existing(assetId);
        Membership storage m = _members[assetId][wallet];
        if (m.status != Status.Active) revert NotActiveMember(wallet);
        Role role = m.role;
        _requireCanManage(assetId, asset, role);

        delete _members[assetId][wallet];
        emit RoleRevoked(assetId, wallet, role, msg.sender);
    }

    // ---------------------------------------------------------------- part B: equipment

    /// B1, B2, B7: add a unit. The holder's change applies at once (applied = true, id = unit);
    /// an active asset manager's becomes a proposal (applied = false, id = proposal).
    function addUnit(uint256 assetId, UnitInput calldata spec) external returns (bool applied, uint256 id) {
        _validateUnit(spec);
        return _applyOrPropose(assetId, ProposalKind.AddUnit, abi.encode(spec));
    }

    /// B1, B6: mark a unit replaced and add its replacement, in one action.
    function replaceUnit(uint256 assetId, uint256 oldUnitId, UnitInput calldata newSpec, uint64 replacedAt)
        external
        returns (bool applied, uint256 id)
    {
        _validateUnit(newSpec);
        _validateReplace(assetId, oldUnitId, newSpec.system, replacedAt);
        return _applyOrPropose(assetId, ProposalKind.ReplaceUnit, abi.encode(oldUnitId, newSpec, replacedAt));
    }

    /// B1, B7: extend a unit's warranty to a later end date (appended, never edited).
    function extendWarranty(uint256 assetId, uint256 unitId, uint64 newEnd) external returns (bool applied, uint256 id) {
        _validateExtend(assetId, unitId, newEnd);
        return _applyOrPropose(assetId, ProposalKind.ExtendWarranty, abi.encode(unitId, newEnd));
    }

    /// B1: only the holder confirms; the change is checked again and applied as proposed.
    function confirmProposal(uint256 assetId, uint256 proposalId) external {
        Asset storage asset = _existing(assetId);
        if (msg.sender != asset.holder) revert NotAuthorized(msg.sender);
        Proposal storage p = _existingProposal(assetId, proposalId);
        if (p.status != ProposalStatus.Pending) revert ProposalNotPending(proposalId);
        p.status = ProposalStatus.Confirmed;
        emit ProposalConfirmed(assetId, proposalId);
        _apply(assetId, p.kind, p.payload, p.proposer);
    }

    /// B1: the asset manager that proposed a change can withdraw it while it is pending.
    function withdrawProposal(uint256 assetId, uint256 proposalId) external {
        _existing(assetId);
        Proposal storage p = _existingProposal(assetId, proposalId);
        if (msg.sender != p.proposer) revert NotAuthorized(msg.sender);
        if (p.status != ProposalStatus.Pending) revert ProposalNotPending(proposalId);
        p.status = ProposalStatus.Withdrawn;
        emit ProposalWithdrawn(assetId, proposalId);
    }

    /// B11: anyone can read a unit, with its current warranty end (0 = no warranty).
    function getUnit(uint256 assetId, uint256 unitId) external view returns (Unit memory unit, uint64 warrantyEndNow) {
        _existing(assetId);
        Unit storage u = _existingUnit(assetId, unitId);
        return (u, _currentWarrantyEnd(assetId, unitId));
    }

    /// B11: the appended warranty extensions of a unit, oldest first.
    function warrantyExtensions(uint256 assetId, uint256 unitId) external view returns (uint64[] memory) {
        _existing(assetId);
        _existingUnit(assetId, unitId);
        return _extensions[assetId][unitId];
    }

    /// B11: anyone can read a proposal.
    function getProposal(uint256 assetId, uint256 proposalId) external view returns (Proposal memory) {
        _existing(assetId);
        return _existingProposal(assetId, proposalId);
    }

    function _applyOrPropose(uint256 assetId, ProposalKind kind, bytes memory payload)
        private
        returns (bool applied, uint256 id)
    {
        Asset storage asset = _existing(assetId);
        if (msg.sender == asset.holder) {
            return (true, _apply(assetId, kind, payload, msg.sender));
        }
        Membership storage m = _members[assetId][msg.sender];
        if (m.role != Role.AssetManager || m.status != Status.Active) revert NotAuthorized(msg.sender);
        id = ++proposalCount[assetId];
        _proposals[assetId][id] = Proposal(kind, ProposalStatus.Pending, msg.sender, payload);
        emit ProposalMade(assetId, id, kind, msg.sender);
        return (false, id);
    }

    function _apply(uint256 assetId, ProposalKind kind, bytes memory payload, address author)
        private
        returns (uint256 unitId)
    {
        if (kind == ProposalKind.AddUnit) {
            UnitInput memory spec = abi.decode(payload, (UnitInput));
            return _addUnit(assetId, spec, 0, author);
        }
        if (kind == ProposalKind.ReplaceUnit) {
            (uint256 oldId, UnitInput memory spec, uint64 replacedAt) = abi.decode(payload, (uint256, UnitInput, uint64));
            _validateReplace(assetId, oldId, spec.system, replacedAt); // state may have changed since proposing
            unitId = _addUnit(assetId, spec, oldId, author);
            Unit storage old = _units[assetId][oldId];
            old.replacedAt = replacedAt;
            old.replacedBy = unitId;
            emit UnitReplaced(assetId, oldId, unitId, replacedAt, author);
            return unitId;
        }
        (uint256 uid, uint64 newEnd) = abi.decode(payload, (uint256, uint64));
        _validateExtend(assetId, uid, newEnd); // state may have changed since proposing
        _extensions[assetId][uid].push(newEnd);
        emit WarrantyExtended(assetId, uid, newEnd, author);
        return uid;
    }

    function _addUnit(uint256 assetId, UnitInput memory spec, uint256 replaces, address author)
        private
        returns (uint256 unitId)
    {
        unitId = ++unitCount[assetId];
        Unit storage u = _units[assetId][unitId];
        u.spec = spec;
        u.replaces = replaces;
        emit UnitAdded(assetId, unitId, spec, author);
    }

    function _validateUnit(UnitInput calldata spec) private view {
        _checkText(spec.name, "name", true);
        _checkText(spec.oem, "oem", true);
        _checkText(spec.model, "model", false);
        _checkText(spec.rating, "rating", false);
        if (spec.system == 0) revert InvalidSystem();
        if (spec.quantity == 0) revert ZeroQuantity();
        if (spec.inService == 0) revert EmptyField("inService");
        if (spec.inService > block.timestamp) revert DateInFuture();
        bool none = spec.warrantyStart == 0 && spec.warrantyEnd == 0;
        if (!none && spec.warrantyEnd <= spec.warrantyStart) revert InvalidWarranty();
    }

    function _validateReplace(uint256 assetId, uint256 oldUnitId, uint16 newSystem, uint64 replacedAt) private view {
        _existing(assetId);
        Unit storage old = _existingUnit(assetId, oldUnitId);
        if (old.replacedAt != 0) revert AlreadyReplaced(oldUnitId);
        if (newSystem != old.spec.system) revert SystemMismatch();
        if (replacedAt > block.timestamp) revert DateInFuture();
        if (replacedAt < old.spec.inService) revert ReplacementBeforeInService();
    }

    function _validateExtend(uint256 assetId, uint256 unitId, uint64 newEnd) private view {
        _existing(assetId);
        Unit storage u = _existingUnit(assetId, unitId);
        if (u.spec.warrantyEnd == 0) revert NoWarranty(unitId);
        if (u.replacedAt != 0) revert AlreadyReplaced(unitId);
        if (newEnd <= _currentWarrantyEnd(assetId, unitId)) revert ExtensionNotLater();
    }

    function _currentWarrantyEnd(uint256 assetId, uint256 unitId) private view returns (uint64) {
        uint64[] storage ext = _extensions[assetId][unitId];
        return ext.length == 0 ? _units[assetId][unitId].spec.warrantyEnd : ext[ext.length - 1];
    }

    function _existingUnit(uint256 assetId, uint256 unitId) private view returns (Unit storage) {
        if (unitId == 0 || unitId > unitCount[assetId]) revert UnknownUnit(unitId);
        return _units[assetId][unitId];
    }

    function _existingProposal(uint256 assetId, uint256 proposalId) private view returns (Proposal storage) {
        if (proposalId == 0 || proposalId > proposalCount[assetId]) revert UnknownProposal(proposalId);
        return _proposals[assetId][proposalId];
    }

    /// C9: anyone can read a wallet's role, status and company on an asset
    /// (Role.None / Status.None for wallets without a role).
    function roleOf(uint256 assetId, address wallet)
        external
        view
        returns (Role role, Status status, string memory company)
    {
        _existing(assetId);
        Membership storage m = _members[assetId][wallet];
        return (m.role, m.status, m.company);
    }

    /// C2: the holder manages both roles; an active asset manager manages O&M providers only.
    function _requireCanManage(uint256 assetId, Asset storage asset, Role role) private view {
        if (msg.sender == asset.holder) return;
        Membership storage caller = _members[assetId][msg.sender];
        if (
            role == Role.OmProvider && caller.role == Role.AssetManager && caller.status == Status.Active
        ) return;
        revert NotAuthorized(msg.sender);
    }

    function _existing(uint256 assetId) private view returns (Asset storage) {
        if (assetId == 0 || assetId > assetCount) revert UnknownAsset(assetId);
        return _assets[assetId];
    }

    function _checkText(string calldata text, string memory field, bool required) private pure {
        uint256 length = bytes(text).length;
        if (required && length == 0) revert EmptyField(field);
        if (length > MAX_TEXT_BYTES) revert TextTooLong(field);
    }
}
