import { describe, it } from "node:test";
import assert from "node:assert/strict";
import hre from "hardhat";

// Rule A8: identity is fixed at registration, so the contract must have no function
// that could edit it. This test lists every function that can change the contract's
// state. Any new one - in later parts or by mistake - makes this test fail until it
// is added to the list below deliberately, with the rule that allows it.
const ALLOWED_STATE_CHANGING = [
  "registerAsset", // A1-A7
  "inviteRole", // C2-C4, C6
  "withdrawInvitation", // C2-C3
  "acceptRole", // C3
  "revokeRole", // C2, C7
  "addUnit", // B1-B2, B7
  "replaceUnit", // B1, B6
  "extendWarranty", // B1, B7
  "confirmProposal", // B1
  "withdrawProposal", // B1
  "submitEntry", // D1-D5, D7, D8
  "confirmEntry", // D6, D8, D9, D11
  "proposeTransfer", // E1-E4
  "cancelTransfer", // E2
  "acceptTransfer", // E1, E4-E8
];

describe("AssetPassport interface (rules A8, C11, B12, D10, D15, E11)", () => {
  it("has no state-changing functions other than the allowed list", async () => {
    const artifact = await hre.artifacts.readArtifact("AssetPassport");
    const changing = artifact.abi
      .filter((e: any) => e.type === "function")
      .filter((e: any) => e.stateMutability !== "view" && e.stateMutability !== "pure")
      .map((e: any) => e.name)
      .sort();
    assert.deepEqual(changing, [...ALLOWED_STATE_CHANGING].sort());
  });
});
