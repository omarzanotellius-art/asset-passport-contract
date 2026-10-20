# Technical details

How the asset passport is built, tested and run: the contract and its rules, the tests, the demo data, the script that recorded both passports on Polygon Amoy, and the passport pages. For what the project is and why, see the [README](../README.md).

> A learning project. Not audited. Runs on a public **test** network with fictional data.

---

## Contents

1. [Repository map](#1-repository-map)
2. [Toolchain and quick start](#2-toolchain-and-quick-start)
3. [The contract](#3-the-contract)
4. [Tests](#4-tests)
5. [Demo data and documents](#5-demo-data-and-documents)
6. [The demo script](#6-the-demo-script)
7. [The live run on Amoy](#7-the-live-run-on-amoy)
8. [The passport pages](#8-the-passport-pages)
9. [Verification](#9-verification)
10. [Limitations and what real use would need](#10-limitations-and-what-real-use-would-need)

---

## 1. Repository map

```
contracts/AssetPassport.sol        the contract
test/                              129 tests: rules by part, full story of both farms, interface guard
demo/
  wildrye.actions.json             Wildrye's history: 41 contract calls, in order
  verrow.actions.json              Verrow's history: 61 contract calls, in order
  illustrative.json                data-page fields that are not on the network
  evidence/                        11 fictional documents in 10 sets, each with manifest.json
scripts/
  demo.ts                          records both passports (local rehearsal or Amoy), resumable
  wallets.ts                       read-only: the ten demo wallets and their balances
  viewer-data.ts                   the passport pages' data files, from a finished run
  viewer-snapshot.ts               the pages' fallback copy (saved only if two reads agree)
  build-viewer-lib.mjs             reproducible single-file bundle of viem
  build-publish.mjs                the bundle published on the blog, with SHA256SUMS
viewer/
  index.html                       the passport page
  loader.mjs                       reads both passports from the chain
  lib/viem-2.56.8.js               the self-hosted viem bundle
  data/                            network settings, contract interface, overlay, illustrative data, snapshot
  test/                            checks of the loader and snapshot against the reviewed design
  blog/components.html             ready-made blocks for the blog post
deployments/
  amoy-demo.json                   every step of the live run and its transaction
  amoy-overlay.json                simulated recorded dates, by transaction
hardhat.config.ts                  the Amoy network; secrets by name only
.gitattributes                     evidence files never altered on checkout
```

`publish/` (the built bundle) and local-chain files are not committed.

---

## 2. Toolchain and quick start

- **Hardhat 3.17.0** with viem and Node's test runner; **Solidity 0.8.37** (npm's `solc`); **forge-std v1.16.2** for Solidity tests.
- **viem 2.56.8**, pinned by `package-lock.json`, used by the tests, the script and the passport pages alike.
- Developed in **GitHub Codespaces**, because the toolchain wouldn't run on the Windows on ARM machine used for this project.

```
npm install
npm run build
npm test
```

You should see `129 passing`.

**Rehearse the whole demo on a local chain** (spends nothing, takes seconds):

```
npx hardhat run scripts/demo.ts
```

It deploys the contract, records both farms' histories and ends with `Self-check passed: the chain matches the action files.`

---

## 3. The contract

`contracts/AssetPassport.sol` (612 lines). One contract holds any number of passports, numbered 1, 2, 3… (shown as AP-0001, AP-0002…).

**There is no token, no administrator, no upgrade mechanism and no function that edits or deletes anything.** The contract calls no other contracts (it uses only the network's built-in SHA-256 function) and cannot receive funds: it has no payable function, `receive` or `fallback`.

### Functions

| Area | State-changing (15) | Read |
|---|---|---|
| Assets | `registerAsset` | `getAsset`, `holderOf`, `assetCount` |
| Roles | `inviteRole`, `withdrawInvitation`, `acceptRole`, `revokeRole` | `roleOf` |
| Equipment | `addUnit`, `replaceUnit`, `extendWarranty`, `confirmProposal`, `withdrawProposal` | `getUnit`, `warrantyExtensions`, `getProposal`, `unitCount`, `proposalCount` |
| Entries | `submitEntry`, `confirmEntry` | `getEntry`, `entryCount` |
| Control | `proposeTransfer`, `cancelTransfer`, `acceptTransfer` | `pendingHolderOf` |

**Events (16):** `AssetRegistered`, `RoleInvited`, `RoleAccepted`, `RoleRevoked`, `InvitationWithdrawn`, `UnitAdded`, `UnitReplaced`, `WarrantyExtended`, `ProposalMade`, `ProposalConfirmed`, `ProposalWithdrawn`, `EntrySubmitted`, `EntryConfirmed`, `TransferProposed`, `TransferCancelled`, `ControlTransferred`. Every change emits an event with every field, so a passport can be rebuilt from the chain alone; the passport pages do exactly that.

**Errors:** 33 named custom errors (for example `NotAuthorized`, `CategoryNotAllowed`, `HeadlineMismatch`, `AlreadyConfirmed`), so a rejected call says why.

**Limits:** every text field up to **100 bytes** (`MAX_TEXT_BYTES`); entry categories **1–14** (`MAX_CATEGORY`).

### Rules

**Assets and identity**
- Any wallet can register an asset and becomes its **holder**. (A learning-project choice: nothing checks that the registrant owns the asset.)
- Name, state and county are required; municipality, EPC, SPV and legal address are optional. AC capacity in whole kW, above zero; solar and/or battery.
- The identity is fixed once registered. Later facts are recorded as entries.

**Roles**
- Two roles: **asset manager** and **O&M provider**. The holder is not a role.
- A role starts by **invitation**, naming the wallet and its company, and takes effect only when **that wallet accepts**.
- The holder manages both roles; an active asset manager manages O&M providers only. Several wallets can hold the same role.
- Revocation ends rights at once; everything already recorded stays. A revoked wallet can be invited again. There is no "resign" function.

**Equipment**
- The holder adds, replaces and extends units directly. An active asset manager **proposes** the same changes, and they take effect only when the holder confirms them (the holder can't decline; an asset manager can withdraw its own proposal).
- A unit has a name, system, OEM, model, rating, quantity, in-service date, an optional warranty and a "part" flag.
- A **replacement** marks the old unit as replaced on a date and adds the new one, linked both ways, in the same system. The old unit keeps its record and warranty history.
- Warranty extensions are appended, each later than the last, only on units with a warranty that haven't been replaced.

**Entries and confirmation**
- An entry has a category, the date of the event (never in the future), the block's time as its recorded date, a headline, an optional document fingerprint, an optional equipment reference (readable text, such as "Inverter 2") and an optional link to an earlier entry.
- **Categories are restricted by role, in the contract:** O&M providers can write scheduled maintenance (2), unscheduled work (3), replacements (4) and severe weather (13); the holder and asset manager can write all fourteen.
- **The holder's entries** carry their headline text and are confirmed at once; the contract computes and stores the headline's SHA-256.
- **Everyone else's entries** carry only the headline's SHA-256. The confirmer publishes the text, and the contract accepts it only if it matches. Asset-manager entries are confirmed by the holder; O&M entries by the holder or an active asset manager. The confirmer and time are recorded.
- Nothing is edited, deleted or withdrawn. An unconfirmed entry stays pending — visible, with its author and date, but without its wording.
- Each entry keeps a snapshot of its author's role and company, so it stays correctly labelled after the author is revoked.

**Control transfer**
- Two steps: the holder proposes a wallet; control moves only when that wallet accepts. The holder can cancel or replace the proposal first.
- A wallet with a role or a pending invitation can't become holder until that is revoked or withdrawn (checked at proposal and at acceptance).
- The previous holder loses every power at once. Asset managers and providers stay active until the new holder revokes them, and the new holder (or its asset manager, for O&M work) can confirm whatever was left pending.

### Categories

| Code | Category | O&M provider may write |
|---|---|---|
| 1 | Commissioning (shown as a double-ring seal) | — |
| 2 | Scheduled maintenance (round stamp) | ✓ |
| 3 | Unscheduled / corrective work | ✓ |
| 4 | Replacement, revamping, repowering | ✓ |
| 5 | Warranty claim | — |
| 6 | Warranty dispute | — |
| 7 | Insurance claim | — |
| 8 | Operational event | — |
| 9 | Annual production | — |
| 10 | Contract change | — |
| 11 | Contract dispute | — |
| 12 | Environmental or permitting dispute | — |
| 13 | Severe weather | ✓ |
| 14 | Insurance policy | — |

Adding a category, or changing who may write one, needs a new contract. Equipment systems are plain numbers and can be extended without one.

### Conventions used by the demo

- **Holder names.** The contract stores a holder as a wallet only. Each holder records its own name as an entry: category 10, headline starting `Holder name: ` — at registration, and by a new holder after accepting a transfer. A rename would be a new entry; the pages show the current holder's latest one.
- **Production and insurance** are read from fixed headline formats: `2022: 26,200 MWh` and `Property damage (all risk), Granmoor Insurance, 07/2026-07/2027`.
- **Systems:** 1 Inverters, 2 Modules, 3 Transformers, 4 Trackers, 5 Battery storage.

---

## 4. Tests

**129 passing:** assets and identity 20 · roles 25 · equipment 27 · entries and confirmation 30 · control transfer 22 · full story 3 · toolchain 1 · interface guard 1.

- **Every rule is tested both ways:** that it allows what it should and refuses what it shouldn't.
- **Every rule was then deliberately broken** in the contract to prove its test catches the break — 101 breaks, all caught (two were shown to have no possible effect, and are documented as such).
- **The full-story test** (`test/AssetPassport.story.t.sol`) plays both farms from July 2021 to October 2026, moving the clock to each event's date, and checks what each passport shows at the end: holders, parties, the pending entry, the late entry, the dispute's link, the replacement, the counts.
- **The interface guard** (`test/AssetPassport.interface.test.ts`) fails if any state-changing function exists beyond the fifteen listed — so an edit or delete function can't be added unnoticed.

Run a single file:

```
npx hardhat test test/AssetPassport.partD.t.sol
```

---

## 5. Demo data and documents

### The action files

`demo/wildrye.actions.json` (41 actions: 18 entries, 9 equipment units) and `demo/verrow.actions.json` (61 actions: 25 entries, 10 units) are each farm's history as a **chronological list of contract calls**:

```
{ "n": 26, "date": "2022-10", "by": "brennick", "do": "submitEntry",
  "key": "cableTemp", "category": 3, "eventDate": "2022-10",
  "headline": "Temporary repair", "equipmentRef": "Cable section C",
  "link": null, "evidence": "verrow/cableTemp" }
```

- `n` — position; the script resumes from the last completed one.
- `date` — the **simulated recorded date** (see below).
- `by` — the acting wallet, by name; addresses are attached at run time.
- `do` — the contract function; `key` lets later actions refer to an entry or unit.

Before any chain run, both files were checked against the contract's rules by a simulator (it caught one ordering mistake). `demo/README.md` describes the format in full.

### Simulated recorded dates

Five years of history were recorded in one day, so the contract's recorded dates are all October 2026. The pages show the simulated dates from the action files instead, taken from `deployments/amoy-overlay.json` (transaction → date). The event dates are on the network as shown. A recorded date is shown in bronze when it is two or more months after the event.

### Documents

`demo/evidence/<farm>/<entry>/` holds 11 fictional plain-text documents in 10 sets: both commissioning certificates, Wildrye's tracker motor work order, and Verrow's inverter 2 site report, second call-out, warranty claim, cable section C reports, replacement record, and the manufacturer's response and dispute notice.

- Each folder has a `manifest.json` listing each file's SHA-256. **The SHA-256 of `manifest.json` is what the entry records on-chain.**
- Every document is marked fictional, names companies and roles only, and contains no amounts.
- **`.gitattributes`** tells Git never to change these files on checkout. Without it, Git on Windows converts line endings and the fingerprints stop matching — tested both ways on a simulated Windows checkout.

---

## 6. The demo script

`scripts/demo.ts` records both passports from the action files. The same script runs locally and on Amoy.

| Rule | What it does |
|---|---|
| Order | Deploys, then plays Wildrye's actions, then Verrow's |
| Wallets | Ten wallets from **one recovery phrase**, in a fixed order: 0 funder, 1 Larkmoor, 2 Tavren, 3 Tarrow, 4 Halvern, 5 Ostrell, 6 Pellam, 7 Quenby, 8 Brennick, 9 Dalbeck. Locally, Hardhat's built-in accounts take the same positions |
| Resumable | Progress is saved after every step (`deployments/<network>-demo.json`). If interrupted after sending, a re-run **waits for that same transaction** — nothing is sent twice |
| Instalments | Before each farm, a pre-flight check confirms the funder can cover it; if not, the run **pauses cleanly** before spending anything on that farm |
| Top-ups and refills | The funder tops up each farm's parties to their measured need; before each action, if the sender can't afford that action's own gas estimate (×1.3), the funder refills it first |
| Fees | 30 gwei priority fee (Polygon rejects tips below 25 gwei); maximum fee = 2 × base fee + tip |
| Safety | Refuses to start on a live network while any placeholder text remains in the data |
| Self-check | At the end, reads the chain and compares the final state with the action files: holders, active parties, counts, the pending entry, every headline, date, equipment reference, document fingerprint, link and author |
| Overlay | Writes `deployments/<network>-overlay.json` (transaction → simulated recorded date) |
| Secrets | `AMOY_RPC_URL` and `AMOY_MNEMONIC`, referred to by name only and stored in Hardhat's encrypted keystore |

### Rehearsals

```
npx hardhat run scripts/demo.ts                                   # in-process chain
npx hardhat node                                                  # second terminal
DEMO_INTERRUPT_AT="verrow #24" npx hardhat run scripts/demo.ts --network localhost
npx hardhat run scripts/demo.ts --network localhost              # resumes
```

`DEMO_INTERRUPT_AT` stops right after **sending** a step — the hardest case to resume. `DEMO_FORCE_PREFLIGHT=1` applies the instalment checks and refills on a local chain too, for rehearsing pauses with deliberately low balances.

### Running it on Amoy

```
npx hardhat keystore set AMOY_RPC_URL        # e.g. https://polygon-amoy-bor-rpc.publicnode.com
npx hardhat keystore set AMOY_MNEMONIC       # the twelve words
npx hardhat run scripts/wallets.ts --network amoy     # read-only: addresses and balances
npx hardhat run scripts/demo.ts --network amoy
```

Re-running the last command after any stop or pause continues where it left off.

---

## 7. The live run on Amoy

**Contract:** [`0x024f7b7064ff3f824105563c443fb6db5365bdf2`](https://amoy.polygonscan.com/address/0x024f7b7064ff3f824105563c443fb6db5365bdf2) · recorded on 19 October 2026 · **self-check passed.**

### What happened

1. **Instalment 1** deployed the contract and recorded Wildrye's steps 1–36, then **stopped at step 37**: one party's wallet ran out of gas. Nothing was lost; the stopped step had never been sent.
2. **Diagnosis:** the progress file records the gas of every step. Comparing it with the local rehearsal showed gas on Amoy **12% to 32% above** local measurements, depending on the kind of step (confirmations highest) — more than the 20% margin the top-ups allowed.
3. **Fix:** local measurements scaled by ×1.35 for Amoy, and the just-in-time refill (§6), both rehearsed locally first.
4. **Resume:** the refill topped up the short wallet, Wildrye completed, and the run **paused cleanly before Verrow** until more test POL arrived.
5. **Instalment 2:** Verrow's 61 steps, with no refills needed. **Self-check passed** for both farms.

**Gas used** (≈ 22.4 million in all, ≈ 0.67 POL at 30 gwei): funder 4,419,764 (deploy and transfers) · Larkmoor 5,648,838 · Tavren 711,805 · Tarrow 1,217,153 · Halvern 6,105,473 · Ostrell 1,632,170 · Pellam 266,193 · Quenby 266,193 · Brennick 1,548,741 · Dalbeck 630,445.

**Test POL:** public faucets pay little, and increasingly ask for a history on Ethereum mainnet before paying out. The run was funded in instalments as test POL arrived, which is why the script was built to pause cleanly between farms.

### Wallets

| # | Party | Address |
|---|---|---|
| 0 | Funder | `0x67a5ed1307E32C79B8BBAf2fd78cA44B72Ef281D` |
| 1 | Larkmoor Capital (Wildrye holder) | `0x3304404E980475544867386015266F84d964A2b7` |
| 2 | Tavren Asset Management | `0x6EFAe8EF125DA09D5041f51fdFD0B68A98B8907a` |
| 3 | Tarrow Field Services | `0x458c8A863278d574F12e3ebb8738b58bFc78C2bC` |
| 4 | Halvern Capital (Verrow holder to Feb 2025) | `0x16Ef78b47B957D0737D3aB4EB977F178e9c0e8D5` |
| 5 | Ostrell Capital (Verrow holder from Feb 2025) | `0x3F6d5771A513C8f96aca7Ad30bADbC9D083C1408` |
| 6 | Pellam Asset Services | `0x51846A4C826b054e7aCf49aDeD8c84E3Ed9c6D3c` |
| 7 | Quenby Energy Management | `0x8788518e283f9246370f5206A5A9acE629F5428f` |
| 8 | Brennick O&M | `0x8c3C25E224147Fe547B37222d8E0f25839858CE4` |
| 9 | Dalbeck Solar Services | `0x0DE756684AA36B38F1D9c0970E9f1f4c615Bd362` |

All ten were used on the test network by the script that played every party. Do not send real funds to any of them.

---

## 8. The passport pages

The pages are written and tested here (`viewer/`) and copied to the blog's `passport/` folder for publication. They are **read-only**: they never send a transaction or ask for a wallet.

### How they read the chain

- **`lib/viem-2.56.8.js`** — a **self-hosted, single-file bundle of the exact viem version** locked in `package-lock.json`, so visitors run the same code the tests ran, with no third-party script at view time. 327,521 bytes, SHA-256 `4e2568fa81f950aecec6d50ebdeacde26b16e9365f367af196619885727133be`. Rebuild and check: `node scripts/build-viewer-lib.mjs` (reproducible: identical bytes on two machines).
- **`loader.mjs`** reads both passports — identity, equipment, warranties, parties and their periods (from events), every entry with its transaction — and returns them in exactly the shape the page design uses. It reads events only within the demo's block range, in chunks a public RPC accepts.
- **`index.html`** reads the chain in parallel with a **12-second limit**. If the read fails or takes longer, it shows **`data/snapshot.json`**, the copy kept in this repository, with a banner giving the date the copy was made.

### Data files (`viewer/data/`)

`config.json` (network, contract, block range, explorer), `abi.json` (the contract's interface), `overlay.json` (simulated recorded dates), `illustrative.json`, `snapshot.json`. Made by:

```
npx hardhat run scripts/viewer-data.ts --network amoy
npx hardhat run scripts/viewer-snapshot.ts --network amoy
```

The snapshot script reads the chain **twice** with the same loader the page uses and saves only if both reads are identical.

### Proven equal to the reviewed design

- `node viewer/test/compare-snapshot.mjs` compares the live record, field by field, with `viewer/test/expected-demo.json` — the data the page design was built and reviewed with. **Zero differences.** (`compare-demo.mjs` does the same against a local chain.)
- In a headless browser, the text of **every spread of both passports** was compared with the reviewed design: identical, 14 of 14 each.
- Every explorer link was checked to be a real transaction.

### Page behaviour

- Address: `/passport/?asset=AP-0001`; sections are linkable, e.g. `?asset=AP-0002#maintenance-2024`, `#wallets`, `#claims`.
- A **"Go to section"** menu lists every section, with maintenance by year.
- A **↗** marks every explorer link: each stamp and entry (after its date), the current holder, the last transfer, and every wallet on the Wallets page.
- Desktop shows two-page spreads; phones show one page at a time, with no sideways scrolling down to 320 px; light and dark mode.

### Publishing

```
node scripts/build-publish.mjs
```

builds `publish/passport/` (exactly eight files) and `publish/passport.zip`, plus **`SHA256SUMS`**, published alongside so anyone can check what the blog serves. It refuses to build if the data isn't for Polygon Amoy, if the snapshot and settings point at different contracts, or if the viem bundle doesn't match its recorded fingerprint.

---

## 9. Verification

| What | How |
|---|---|
| A passport entry | Follow its ↗ link to the transaction on the explorer |
| Every step of the run | `deployments/amoy-demo.json` lists each step and its transaction |
| A document | Fingerprint it, compare with `manifest.json`, fingerprint the manifest, find that value in the entry's transaction input — see the README's *Verify a record yourself* |
| The published pages | In the top folder, with the files' subfolders (`lib/`, `data/`) kept: `sha256sum -c SHA256SUMS` (Linux, or Git Bash on Windows) or `shasum -a 256 -c SHA256SUMS` (macOS). PowerShell has no equivalent; compare each file with `Get-FileHash` |
| The pages match the reviewed design | `node viewer/test/compare-snapshot.mjs` |
| The contract's source code | **Pending:** verification on amoy.polygonscan.com. Until then the explorer shows bytecode only, and transaction inputs appear undecoded |

---

## 10. Limitations and what real use would need

**Deliberate shortcuts in this pilot:** anyone can register an asset; identity can't be updated after registration; a replacement entry and the equipment change are separate records the contract doesn't link; categories are fixed; providers can't resign; production and insurance rely on headline formats; holder names rely on a category-10 convention; there is no way to contest an entry.

**Real use would need, at least:** a way to check who may register a real asset and that a wallet belongs to the company it names; updatable identity with its history; replacement entries that update equipment; structured fields for production and insurance; a dedicated category for holder names; a way for the owner to record disagreement with an entry; and, above all, the private model described in the README — the owner choosing which headlines are public, with everything else fingerprint-only.

**Not built (possible next steps):** contesting entries, correction entries, deadlines for confirmation, an automated monitoring role, and a "verify this document" tool on the pages.

---

Copyright © 2026 OnToken, LLC. Free to use under the [MIT License](../LICENSE): anyone may use, copy and adapt it, at their own risk and with no warranty.
