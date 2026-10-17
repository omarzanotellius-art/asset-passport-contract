// Builds viewer/lib/viem-<version>.js: one self-contained file of the EXACT viem version
// pinned in package-lock.json, so visitors run the same bytes we tested (no CDN at view time).
//   node scripts/build-viewer-lib.mjs
import { build } from "esbuild";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";

const version = JSON.parse(readFileSync("node_modules/viem/package.json", "utf8")).version;
const out = `viewer/lib/viem-${version}.js`;
await build({
  entryPoints: ["viewer/lib/viem-entry.mjs"],
  bundle: true,
  format: "esm",
  platform: "browser",
  target: "es2020",
  minify: true,
  legalComments: "eof",
  outfile: out,
});
const bytes = readFileSync(out);
console.log(`${out}: ${bytes.length.toLocaleString()} bytes, sha256 ${createHash("sha256").update(bytes).digest("hex")}`);
