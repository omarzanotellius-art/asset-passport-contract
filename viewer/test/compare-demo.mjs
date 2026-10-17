// Rule L12: the loader, run against a local chain playing the demo, must return exactly the data
// the passport design expects (viewer/test/expected-demo.json) — addresses and links excluded.
//
//   1. npx hardhat node                                        (second terminal)
//   2. npx hardhat run scripts/demo.ts --network localhost
//   3. node viewer/test/compare-demo.mjs
import { readFileSync } from "node:fs";
import { createPublicClient, http } from "viem";
import { hardhat } from "viem/chains";
import { loadPassports } from "../loader.mjs";

const IGNORE = ["w", "address", "tx", "holder", "holderAddress", "registeredTx", "system", "yield", "holderName"];
const expected = JSON.parse(readFileSync("viewer/test/expected-demo.json", "utf8")).passports;
const abi = JSON.parse(readFileSync("artifacts/contracts/AssetPassport.sol/AssetPassport.json", "utf8")).abi;
const state = JSON.parse(readFileSync("deployments/localhost-demo.json", "utf8"));
const overlay = JSON.parse(readFileSync("deployments/localhost-overlay.json", "utf8"));
const client = createPublicClient({ chain: hardhat, transport: http("http://127.0.0.1:8545") });
const got = await loadPassports({
  client, contract: state.contract, abi, fromBlock: 0n, toBlock: await client.getBlockNumber(),
  overlay, illustrative: JSON.parse(readFileSync("demo/illustrative.json", "utf8")),
});

const strip = (x) => JSON.parse(JSON.stringify(x, (k, v) => (IGNORE.includes(k) ? undefined : v)));
const diffs = [];
function cmp(path, a, b) {
  if (Array.isArray(a) || Array.isArray(b)) {
    if (!Array.isArray(a) || !Array.isArray(b) || a.length !== b.length) return diffs.push(`${path}: different length or shape`);
    return a.forEach((x, i) => cmp(`${path}[${i}]`, x, b[i]));
  }
  if (a && typeof a === "object" && b && typeof b === "object") {
    for (const k of new Set([...Object.keys(a), ...Object.keys(b)])) cmp(`${path}.${k}`, a[k], b[k]);
    return;
  }
  const empty = (v) => v === undefined || v === "";
  if (a !== b && !(empty(a) && empty(b))) diffs.push(`${path}: expected ${JSON.stringify(b)}, got ${JSON.stringify(a)}`);
}
for (const no of Object.keys(expected)) cmp(no, strip(got[no]), expected[no]);
// every recorded item must carry its transaction (explorer links, L9)
for (const [no, p] of Object.entries(got)) for (const e of p.entries) if (!e.tx) diffs.push(`${no}: entry ${e.event} ${e.kind} has no transaction`);

if (diffs.length) { console.log(diffs.join("\n")); console.log(`\nLOADER CHECK FAILED: ${diffs.length} difference(s)`); process.exitCode = 1; }
else console.log("Loader check passed: the chain gives exactly the data the design expects, every row with its transaction.");
