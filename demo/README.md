# Demo data

The two fictional farms of the asset passport demo, as **chronological action lists** that the demo script (Stage 2 part C) replays on the chain, top to bottom. Spec: v1.6, §8–§9 and Annex A.

| File | Contents |
|---|---|
| `wildrye.actions.json` | AP-0001 Wildrye Solar — 40 actions: one holder throughout, nothing pending |
| `verrow.actions.json` | AP-0002 Verrow Solar — 59 actions: inverter 2, cable section C, a dispute, a late entry, a pending entry, a sale |
| `illustrative.json` | Data-page details that are **not** on the network and not anchored (D40): COD, developer, grid connection, DC capacity and ratio, energization, typology, orientation; and the modules' performance warranty |
| `evidence/` | Fictional documents for 10 key entries, each folder with a `manifest.json` |

## Format

Each action is one contract call:

```
{ "n": 12, "date": "2022-04", "by": "brennick", "do": "submitEntry", ... }
```

- `n` — position in the list; the script resumes from the last completed `n`.
- `date` — the **simulated recorded date**. On Amoy every action is recorded at the real time of the live run; these dates go into the demo-only overlay file (D51). `YYYY-MM` means the 1st of the month; `YYYY-MM-DD` a specific day; times are 12:00 UTC.
- `by` — the acting wallet, **by name** (`halvern`, `brennick`, …). Real Amoy addresses are attached in part D from the encrypted keystore.
- `do` — the contract function: `registerAsset`, `inviteRole`, `acceptRole`, `revokeRole`, `addUnit`, `replaceUnit`, `extendWarranty`, `submitEntry`, `confirmEntry`, `proposeTransfer`, `acceptTransfer`.
- `key` — a name for an entry or unit, so later actions can refer to it (`confirmEntry` → `entry`, `link`, `extendWarranty` → `unit`). The script maps keys to the numbers the contract assigns.

For entries, `headline` is the text. The script sends the text for the holder's entries, and only its SHA-256 fingerprint for everyone else's; the confirmer then publishes the text (D79).

Categories and systems are numbers from the format document (spec §9, §13.4). Systems: 1 Inverters, 2 Modules, 3 Transformers, 4 Trackers, 5 Battery storage.

## Documents (evidence)

Ten entries carry documents: both commissioning certificates, Wildrye's tracker motor work order, and Verrow's inverter 2 trip, second call-out, warranty claim, cable section C reports, inverter replacement and dispute. Each folder in `evidence/<farm>/<entry>/` holds plain-text documents and a `manifest.json` listing each file's SHA-256 fingerprint. **The fingerprint of `manifest.json` is what the entry records on-chain** — the same method as om-pilot-contract.

Every document is marked as fictional, names companies and roles only (never individuals) and contains no monetary amounts (D21). In real use, documents would stay private: only their fingerprints are public.

`.gitattributes` tells Git never to change these files on checkout. Without it, Git on Windows can convert line endings, which changes the fingerprint.

### Verify a document yourself
1. Download the repository (don't copy and paste a document's text: that can change invisible characters).
2. Fingerprint a document with the tool already on your computer, in its folder:
   - Windows (PowerShell): `Get-FileHash -Algorithm SHA256 inspection-report.txt`
   - macOS: `shasum -a 256 inspection-report.txt`
   - Linux: `sha256sum inspection-report.txt`
3. Compare it with the value next to that file in the folder's `manifest.json` (upper or lower case doesn't matter).
4. Fingerprint `manifest.json` the same way: that value is the one recorded on-chain with the entry.

## Placeholders

`[Municipality A]` and `[Municipality B]` wait for the EIA-860 check (D50). **They must be replaced before the live run**; the script refuses to send placeholders to Amoy.
