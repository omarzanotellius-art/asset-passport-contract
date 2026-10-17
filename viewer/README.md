# Passport viewer

The public viewer for the asset passport demo, written and tested here and **copied to the blog repository** (`the_unlisted_brief`, folder `passport/`) for each publication. Spec v1.7, Stage 3.

## `lib/` — the self-hosted viem bundle

The viewer reads the chain with **viem 2.56.8** — the exact version pinned in `package-lock.json`, used by the contract's tests and the demo script. It is bundled into one file and **hosted with the viewer**, so visitors run the same bytes we tested, with no third-party CDN at view time.

| File | |
|---|---|
| `lib/viem-entry.mjs` | What the bundle contains: only what's needed to read the chain (`createPublicClient`, `http`, `fallback`, the Amoy and local chain definitions) |
| `lib/viem-2.56.8.js` | The bundle (327,521 bytes) |

**Fingerprint (SHA-256) of `lib/viem-2.56.8.js`:**
`4e2568fa81f950aecec6d50ebdeacde26b16e9365f367af196619885727133be`

### Rebuild and verify

```
node scripts/build-viewer-lib.mjs
```

The build is reproducible: it prints the file's size and SHA-256, which must match the values above. If a future viem upgrade changes the lock file, rebuild, re-test, and update both values here.

## `loader.mjs` — from the chain to the design (Stage 3B)

Reads both passports from the contract and returns them in **exactly the shape the passport design uses** (rules L1–L12, spec v1.8). It is read-only: it never sends a transaction or asks for a wallet. It runs in the browser (with `lib/viem-2.56.8.js`) and in Node (tests; the fallback snapshot in 3D), because it only uses the client it is given.

- **Holder names** come from the holders' own `Holder name: ` entries (category 10); a holder entry is signed with the name its author recorded.
- **Production and insurance policies** are read from their headlines, in the fixed formats `2022: 26,200 MWh` and `Property damage (all risk), Granmoor Insurance, 07/2026-07/2027`.
- **Recorded dates** come from the overlay file (simulated dates, D51), otherwise the block's real time.
- **Events** are read only within the demo's block range, in chunks a public RPC accepts.

### Check (rule L12)

```
npx hardhat node                                     (second terminal)
npx hardhat run scripts/demo.ts --network localhost
node viewer/test/compare-demo.mjs
```

It compares the loader's output, field by field, with `test/expected-demo.json` — the reviewed interactive demo's data, without addresses and transaction links — and checks every row has its transaction. Tested both ways: a wrong dispute note and missing transaction links each make it fail.
