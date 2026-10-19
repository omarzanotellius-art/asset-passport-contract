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

## `index.html` — the passport page (Stage 3C)

The reviewed interactive demo's design, **unchanged in appearance** (D37), with its sample data replaced by the loader. What changed, and only this:

- `assets()` returns the loader's data; explorer links (stamps, entries, current holder, last transfer — as in the design) point to the real transactions and addresses.
- System names come from the loader; the "other passports" link and passport switching use `?asset=AP-000x`.
- Sections can be linked: `?asset=AP-0002#maintenance-2024`, `#wallets`, `#claims`, …
- Start-up reads the chain **in parallel** with a **12-second limit**; on failure or time-out it uses `data/snapshot.json` (3D) and shows the archived-copy banner.

### Design changes after the live run (2026-10-19, Omar's decisions)

- **Section bar replaced by one compact menu**, "Go to section", under the page counter: the sections in order, with Maintenance listed by year. It shows the visitor's choice while that page is on screen (otherwise the first section visible).
- **↗ marks every explorer link**: after the date on each entry row and stamp, after the current holder and the last transfer, and on **every wallet on the Wallets page** (linking to the wallet's explorer page, which lists all its transactions). The key explains it: "Items marked ↗ (every stamp, entry and wallet) open their record on the explorer."
- Made in the page and in the reference demo alike. Tested: all 20 menu options open the right page and show the right item; marks visible; no sideways scrolling at 390 and 320 px; key page fits; dark mode readable; every spread identical to the reference (14 of 14 each).

### Data files (`data/`, generated, not committed until the live run)

```
npx hardhat run scripts/viewer-data.ts --network <localhost|amoy>
```

writes `config.json` (network, contract, block range, explorer), `abi.json`, `overlay.json`, `illustrative.json` from a finished demo run.

### Tested (headless Chromium, local chain, 2026-10-18)

The text of **every spread of both passports** is identical to the reviewed demo's (14 of 14 each); no console errors; every explorer link is a real transaction (22 checked); the section link opens the right page; phone (390 px): no sideways scrolling; a dead network shows the failure message after 1.3 s, a silent one after the 12 s limit.

### Disclosures reviewed (Stage 3E, E4 — page side)

Every disclosure on the page was checked against D11, D27, D28, D29, D31, D32, D38, D47, D51 and D85. Two fixes, also made in the reference demo: the illustrative details now include the **modules' performance warranty** (not only data-page fields), and the bronze recorded date is described exactly as the page applies it — **two or more months** after the event (not "more than 30 days"). The key page still fits at 1280, 390 and 320 px; every spread remains identical to the reference (14 of 14 each). The post side of the review waits for the post.

### Fallback snapshot (Stage 3D)

```
npx hardhat run scripts/viewer-snapshot.ts --network <localhost|amoy>
```

Run after `viewer-data.ts`. It reads both passports with **the same loader the page uses**, twice, and saves `data/snapshot.json` only if both reads are identical (it refuses otherwise). The page uses it only when the live read fails or exceeds 12 seconds, with a banner saying when the copy was made. Re-run it whenever the record changes — for the demo, once after the live run.

Tested: with the network cut, both passports render from the snapshot with text identical to the live read on every spread (14 of 14 each), banner and date shown; a deliberately varying read was refused, leaving the previous snapshot untouched.

## `blog/components.html` — for the passport post (Stage 3E)

A preview page with ready-made blocks for the post, in the blog's styles. Copy the marked blocks into the post; the writing around them is Omar's.

1. **The two passports** — covers linking to each passport.
2. **The same pages, side by side** — a neutral list of eight pages (data page, maintenance 2022 and 2024, inverters, claims, awaiting confirmation, production, wallets), each linking to that page in both passports. It names pages, never conclusions (D19).
3. **Questions you might have** — the three FAQ answers (D36).
4. **Call to action** — optional in the post; it is on every passport page too (D29).
5. **The small print** — test network, fiction, simulated dates, illustrative fields, the real-use model (D11, D28, D38, D51).

Tested: all 18 passport links open the right passport on the right page; no sideways scrolling at 390 and 320 px; link colour `#7A5A40` on cream has 5.6:1 contrast (the blog's own `#B07A4E` has 3.3:1, below the 4.5:1 standard).

### Publishing (later)

```
node scripts/build-publish.mjs
```

builds `publish/passport/` and `publish/passport.zip` with **exactly** the files the blog's `passport/` folder needs (the page, the loader, the viem bundle, the five data files) and **`SHA256SUMS`**, the fingerprint of each — published too, so anyone can check what the blog serves:

```
cd passport && sha256sum -c SHA256SUMS
```

**Launch prerequisite (E4, finding 3):** the page says *"a full copy of the record is kept in the public repository."* Before publishing, make `asset-passport-contract` public and turn that phrase into a link to it — otherwise the sentence is not true.

It **refuses** to build when the data isn't for Polygon Amoy (`--rehearsal` allows local data, for testing only), when the snapshot and the settings point at different records, or when the viem bundle doesn't match its recorded fingerprint. `publish/` is not committed; it is rebuilt from committed files.

Tested: refusal on local data, on one altered byte in the viem bundle, and on a snapshot from another contract; a rehearsal bundle verified with `sha256sum -c`; served on its own, both passports render with no missing files.
