// Checks the viewer's snapshot (made from the LIVE chain by scripts/viewer-snapshot.ts) against
// the data the design expects — the same comparison as compare-demo.mjs, without needing a chain.
//   node viewer/test/compare-snapshot.mjs
import { readFileSync } from "node:fs";

const IGNORE = ["w", "address", "tx", "holder", "holderAddress", "registeredTx", "system", "yield", "holderName"];
const expected = JSON.parse(readFileSync("viewer/test/expected-demo.json", "utf8")).passports;
const snap = JSON.parse(readFileSync("viewer/data/snapshot.json", "utf8"));
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
for (const no of Object.keys(expected)) cmp(no, strip(snap.passports[no]), expected[no]);
for (const [no, p] of Object.entries(snap.passports)) for (const e of p.entries) if (!e.tx) diffs.push(`${no}: entry ${e.event} ${e.kind} has no transaction`);
console.log(`Snapshot: ${snap.networkName} (chain ${snap.chainId}), contract ${snap.contract}, made ${snap.madeAt}`);
if (diffs.length) { console.log(diffs.join("\n")); console.log(`\nSNAPSHOT CHECK FAILED: ${diffs.length} difference(s)`); process.exitCode = 1; }
else console.log("Snapshot check passed: the live record gives exactly the data the design expects, every row with its transaction.");
