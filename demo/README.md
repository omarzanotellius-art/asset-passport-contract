# Demo data

The two fictional farms of the asset passport demo, as **chronological action lists** that the demo script (Stage 2 part C) replays on the chain, top to bottom. Spec: v1.6, §8–§9 and Annex A.

| File | Contents |
|---|---|
| `wildrye.actions.json` | AP-0001 Wildrye Solar — 40 actions: one holder throughout, nothing pending |
| `verrow.actions.json` | AP-0002 Verrow Solar — 59 actions: inverter 2, cable section C, a dispute, a late entry, a pending entry, a sale |
| `illustrative.json` | Data-page details that are **not** on the network and not anchored (D40): COD, developer, grid connection, DC capacity and ratio, energization, typology, orientation |

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

## Placeholders

`[Municipality A]` and `[Municipality B]` wait for the EIA-860 check (D50). **They must be replaced before the live run**; the script refuses to send placeholders to Amoy.
