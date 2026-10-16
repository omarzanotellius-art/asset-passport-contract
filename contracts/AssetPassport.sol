// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

/// @title Asset passport (learning project, testnet only)
/// @notice A record of what a renewable energy asset is and what has happened to it.
///         Stage 1 part A: assets and identity. Rule numbers (A1-A9) refer to the spec.
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

    /// A2: number of assets registered so far; asset numbers run 1..assetCount.
    uint256 public assetCount;
    mapping(uint256 => Asset) private _assets;

    /// A7: one event carrying the asset number, the holder and every identity field.
    event AssetRegistered(uint256 indexed assetId, address indexed holder, Identity identity);

    error EmptyField(string field);
    error TextTooLong(string field);
    error NoTechnology();
    error ZeroCapacity();
    error UnknownAsset(uint256 assetId);

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
