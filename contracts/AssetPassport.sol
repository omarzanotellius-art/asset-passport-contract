// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

/// @title Asset passport (learning project, testnet only)
/// @notice A record of what a renewable energy asset is and what has happened to it.
///         Stage 1 part A: assets and identity (rules A1-A9).
///         Stage 1 part C: roles, invitations and revocation (rules C1-C11).
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

    /// A2: number of assets registered so far; asset numbers run 1..assetCount.
    uint256 public assetCount;
    mapping(uint256 => Asset) private _assets;
    /// C5: any number of wallets per role; one membership per wallet per asset (C6).
    mapping(uint256 => mapping(address => Membership)) private _members;

    /// A7: one event carrying the asset number, the holder and every identity field.
    event AssetRegistered(uint256 indexed assetId, address indexed holder, Identity identity);

    /// C8: one event per step; the block's timestamp gives the time.
    event RoleInvited(uint256 indexed assetId, address indexed wallet, Role role, string company, address indexed by);
    event InvitationWithdrawn(uint256 indexed assetId, address indexed wallet, Role role, address indexed by);
    event RoleAccepted(uint256 indexed assetId, address indexed wallet, Role role, string company);
    event RoleRevoked(uint256 indexed assetId, address indexed wallet, Role role, address indexed by);

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
