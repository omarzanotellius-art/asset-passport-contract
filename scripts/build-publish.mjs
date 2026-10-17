// Builds the publication bundle for the blog's passport/ folder (Stage 3E, rules P1-P6).
//   node scripts/build-publish.mjs              (real: requires Amoy data)
//   node scripts/build-publish.mjs --rehearsal  (allows local-chain data, for testing only)
// Output: publish/passport/ (with SHA256SUMS) and publish/passport.zip. Not committed (P6).

import { createHash } from "node:crypto";
import { copyFileSync, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { dirname } from "node:path";

const rehearsal = process.argv.includes("--rehearsal");
const fail = (msg) => { console.error(`NOT BUILT: ${msg}`); process.exit(1); };
const sha = (f) => createHash("sha256").update(readFileSync(f)).digest("hex");
const json = (f) => JSON.parse(readFileSync(f, "utf8"));

// P1: exactly these files, nothing else
const FILES = ["index.html", "loader.mjs", "lib/viem-2.56.8.js",
  "data/config.json", "data/abi.json", "data/overlay.json", "data/illustrative.json", "data/snapshot.json"];
for (const f of FILES) if (!existsSync(`viewer/${f}`)) fail(`viewer/${f} is missing (run viewer-data.ts and viewer-snapshot.ts first).`);

// P2: no misleading bundle
const cfg = json("viewer/data/config.json");
const snap = json("viewer/data/snapshot.json");
if (cfg.chainId !== 80002 && !rehearsal) fail(`the data is for chain ${cfg.chainId}, not Polygon Amoy (80002). Use --rehearsal only for testing.`);
if (snap.contract?.toLowerCase() !== cfg.contract?.toLowerCase() || snap.chainId !== cfg.chainId)
  fail(`the snapshot (${snap.contract}, chain ${snap.chainId}) and the settings (${cfg.contract}, chain ${cfg.chainId}) point at different records.`);
if (cfg.chainId === 80002) {
  const run = json("deployments/amoy-demo.json");
  if (run.contract.toLowerCase() !== cfg.contract.toLowerCase()) fail(`the settings' contract differs from the live run's (${run.contract}).`);
}

// P3: the viem bundle must be exactly the recorded bytes
const recorded = /Fingerprint \(SHA-256\) of `lib\/viem-2\.56\.8\.js`:\*\*\s*\n`([0-9a-f]{64})`/.exec(readFileSync("viewer/README.md", "utf8"))?.[1];
if (!recorded) fail("the viem bundle's recorded fingerprint was not found in viewer/README.md.");
if (sha("viewer/lib/viem-2.56.8.js") !== recorded) fail("lib/viem-2.56.8.js does not match its recorded fingerprint.");

// assemble, with the fingerprint list (P4)
rmSync("publish", { recursive: true, force: true });
for (const f of FILES) { mkdirSync(dirname(`publish/passport/${f}`), { recursive: true }); copyFileSync(`viewer/${f}`, `publish/passport/${f}`); }
const sums = FILES.map((f) => `${sha(`publish/passport/${f}`)}  ${f}`).join("\n") + "\n";
writeFileSync("publish/passport/SHA256SUMS", sums);

// P5: one zip, ready to upload
execFileSync("zip", ["-q", "-r", "../passport.zip", "."], { cwd: "publish/passport" });
console.log(`${rehearsal ? "REHEARSAL " : ""}bundle built for ${cfg.networkName} (contract ${cfg.contract}), snapshot made ${snap.madeAt}:`);
console.log(sums.split("\n").filter(Boolean).map((l) => `  ${l.slice(66)}  ${l.slice(0, 12)}…`).join("\n"));
console.log(`  SHA256SUMS\n→ publish/passport.zip — upload its contents to the blog repository's passport/ folder.`);
