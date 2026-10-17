// Makes the viewer's fallback snapshot (Stage 3D, rules F1-F6): both passports read by the
// SAME loader the page uses (F1), saved with where and when they were read (F2). The chain is
// read twice and the snapshot is saved only if both reads agree (F4). Read-only: sends nothing.
// Run after scripts/viewer-data.ts, and again whenever the record changes (F6).
//
//   npx hardhat run scripts/viewer-snapshot.ts --network <localhost|amoy>

import { readFileSync, writeFileSync } from "node:fs";
import { network } from "hardhat";
import { loadPassports } from "../viewer/loader.mjs";

const { viem } = await network.create();
const client = await viem.getPublicClient();
const read = (f: string) => JSON.parse(readFileSync(`viewer/data/${f}`, "utf8"));
const cfg = read("config.json");
if ((await client.getChainId()) !== cfg.chainId) throw new Error(`viewer/data/config.json is for chain ${cfg.chainId}; run viewer-data.ts for this network first.`);
const args = { client, contract: cfg.contract, abi: read("abi.json"), fromBlock: BigInt(cfg.fromBlock), toBlock: BigInt(cfg.toBlock),
               overlay: read("overlay.json"), illustrative: read("illustrative.json"), networkLabel: cfg.mrzNetwork };

const first = JSON.stringify(await loadPassports(args));
const second = JSON.stringify(await loadPassports(args));
if (first !== second) throw new Error("Not saved: two reads of the chain differ (F4). Try again when the record is not changing.");

const snapshot = {
  note: "Archived copy of the passports, shown only if the live read fails or exceeds its time limit (D32). Made by viewer/loader.mjs.",
  madeAt: new Date().toISOString(), chainId: cfg.chainId, networkName: cfg.networkName, contract: cfg.contract,
  fromBlock: cfg.fromBlock, toBlock: cfg.toBlock, passports: JSON.parse(first),
};
writeFileSync("viewer/data/snapshot.json", JSON.stringify(snapshot, null, 2) + "\n");
const p = snapshot.passports;
console.log(`Snapshot saved: ${Object.keys(p).map((k) => `${k} ${p[k].name} (${p[k].entries.length} rows)`).join(", ")}; two reads identical; made ${snapshot.madeAt}.`);
