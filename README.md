# asset-passport-contract

**A record of what a renewable energy asset is and what it has been through, kept with the asset for its whole life — so whoever holds it next can see what they're inheriting, not just what they hold.**

> **Status: exploratory.** A learning project and demonstration. It runs on a public **test** network and records the history of two fictional solar farms. It is not a product, service, offering, investment or security token, and it has not been audited. What is recorded on the network, and what is simulated or illustrative, is set out under [Live demo](#live-demo-polygon-amoy-test-network).

## An example: Wildrye and Verrow

*Wildrye Solar* (AP-0001) and *Verrow Solar* (AP-0002) are two fictional solar farms in Fresno County, California. On paper they are the same: 10 MWac, the same developer, the same equipment, both starting in July 2021. Their passports, covering July 2021 to September 2026, are not.

**Wildrye** has had one owner throughout, with the same asset manager and maintenance provider. Its passport records a scheduled visit every year, one corrective repair to a tracker motor, insurance and annual production. Every entry is confirmed, and each was recorded within a month of the event (simulated recorded dates).

**Verrow**'s passport records:
- five entries about the same inverter: a repair, a warranty claim, a replacement, a dispute over the claim with no resolution recorded, and a second call-out from August 2022 that was recorded in November 2024 (simulated recorded date), three months before the sale;
- four entries about the same cable section, one of them from the previous maintenance provider, never confirmed by the previous owner;
- no scheduled visit in 2024;
- lower production than Wildrye in 2022 and 2023;
- a change of maintenance provider in June 2024, a sale to a new owner in February 2025, and a new asset manager after the sale.

Neither passport says which farm is better. A reader comparing them can see where the work kept returning, which claim has no resolution recorded, which year has no visit, which entry was recorded late, and which was never confirmed. Each of these can be checked on the public network, except the recorded dates, which are simulated in this demo (see [Live demo](#live-demo-polygon-amoy-test-network)).

<!-- PENDING: the two passport links below go live when the bundle is published on the blog. -->
- [Wildrye Solar passport (AP-0001)](https://theunlistedbrief.com/passport/?asset=AP-0001)
- [Verrow Solar passport (AP-0002)](https://theunlistedbrief.com/passport/?asset=AP-0002)

*The location is real; the farms, companies, people and events are fictional, and any resemblance to real companies or people is unintended. Each farm's town is stored in its record but not shown on the pages.*

## What a passport shows

**History: what the asset has been through, in one place.**
- What the asset is and what's installed: each piece of equipment, its warranty and any extensions. Replaced equipment stays in the history, with the dates it was in service.
- What has happened to it: scheduled visits, corrective work, replacements, warranty claims and disputes, insurance, severe weather and annual production, each with the date it happened.
- Who has been responsible for it: every owner, asset manager and maintenance (O&M) provider, with the dates they started and stopped.

**Continuity: the history stays with the asset.**
- When the asset changes hands, its history goes with it. The next owner doesn't have to rebuild it from a data room put together for one deal.
- The record doesn't depend on any one company, so it survives a change of owner, asset manager or provider.
- A previous owner loses the ability to add or confirm anything once control passes, but everything recorded so far stays, with its authors.

**Integrity: what's on record stays on record.**
- Nobody, including the owner or whoever runs the pages, can quietly change or remove an entry. A later change can only be added as a new entry.
- Each entry carries two dates: when it happened and when it was recorded. The recorded date is set by the network, so a history filled in shortly before a sale shows as such. (In this demo, recorded dates are simulated; see [Live demo](#live-demo-polygon-amoy-test-network).)
- Each entry shows who wrote it and who confirmed it. An entry the owner never confirmed stays marked as awaiting confirmation: its wording isn't public, but anyone can see that it exists, who wrote it and when.
- Documents such as inspection reports stay with the parties. Only their fingerprint is recorded, so anyone holding a document can check it hasn't been changed since.

A passport shows what an asset has been through, not whether it's a good asset. Nothing in it labels anything as a risk.

## What it asks in return

Every party that writes in the passport needs a digital wallet: the owner, the asset manager and each maintenance provider. The owner invites the others, and each has to accept before writing anything. Providers record their own work, and the owner or asset manager confirms it before its wording becomes public. Each entry is recorded on a public network, with a small network fee paid by whoever records it. Anything nobody records is simply missing: a passport is only as complete as the parties keep it.

**The main open question: who would write the entries, and why.** In this demo, every entry was written by a script playing all the parties. In practice, each party would have to record its own work, as it happens, over many years, and nothing in the passport makes them do it. One possible reason a provider would: a dated record of its own work can protect it in a dispute over who caused a failure. That is an assumption, not something this project has tested.

## How it works

The passport is kept by a "smart contract": a small program on a public blockchain that stores records and accepts new ones only under rules written in advance. It has no edit or delete function, no administrator and no way to be upgraded. One contract holds any number of passports, each with its own number (AP-0001, AP-0002 and so on).

**Why a blockchain?** Ordinary software with an audit log could do much of this. A blockchain adds three narrow things: there is no operator whose word has to be trusted, the record outlives any one vendor, and anyone can check it without asking permission.

- **Registration.** The owner registers the asset with its identity (name, location, capacity, the company that built it) and becomes its holder: the wallet that controls the passport. Being the holder means controlling the record, not owning an interest in the asset. The identity is fixed from then on.
- **Roles.** The holder invites an asset manager and maintenance providers, each by wallet and company name. An invitation takes effect only when that wallet accepts. The holder can revoke anyone, and an asset manager can revoke maintenance providers. Rights end at once; past entries stay.
- **Equipment.** The holder lists each piece of equipment with its warranty, and records extensions and replacements. An asset manager can propose changes for the holder to confirm.
- **Entries.** Each entry has a category, the date it happened, a short headline and, where there is one, the fingerprint of its documents. Maintenance providers can record only their own kind of work: scheduled visits, corrective work, replacements and severe weather. The holder and the asset manager can also record the rest, such as warranty claims, insurance and production.
- **Confirmation.** The holder's own entries are confirmed as they are recorded. Anyone else's entry awaits confirmation by the holder or, for maintenance work, by the asset manager, and the confirmer and date are recorded. Nothing can be edited or withdrawn: an unconfirmed entry simply stays pending.
- **Change of control.** The holder proposes a new holder, and control moves only when that wallet accepts. From then on, the previous holder can't add or confirm anything. The asset manager and providers stay in place until the new holder decides otherwise, and the new holder can confirm whatever was left pending.
- **The passport pages.** A read-only web page shows each passport as a booklet, read directly from the network. It never asks for a wallet or sends anything.

## Why it matters

Tokenization can make interests in renewable energy assets easier to hold and transfer. But a token doesn't change the question at the heart of every transaction: what is this asset, and what has it been through?

A passport that stays with the asset gives both sides the same record. The seller can show the asset's history without rebuilding a data room for each deal. The buyer can check that record instead of taking it on trust.

There's an incentive for the seller too. Buyers tend to discount what they can't see, so a clear, documented history can be worth more than silence. That is an assumption, not something this project has measured.

## What it doesn't solve

Being clear about the limits is part of the point.

- **It can't tell whether an entry is true.** The record proves who wrote an entry, who confirmed it and when, and a fingerprint proves a document hasn't changed since it was recorded. Neither proves the work happened or that its description is accurate. Entries are still claims made by the parties.
- **It can't show what's missing.** A passport holds only what someone recorded. A gap may mean the work never happened, or that nobody wrote it down.
- **It can't confirm who is behind a wallet.** Company names are entered by the parties themselves. Nothing in this pilot checks that a wallet belongs to the company it names, or that whoever registers an asset actually owns it.
- **It doesn't store the documents.** Only fingerprints are recorded. The documents stay with the parties, and a lost document can no longer be checked.
- **There is no way yet to disagree with an entry.** An owner can confirm an entry or leave it unconfirmed, but can't record that it disputes it. A pending entry can stay pending indefinitely, though it remains visible.
- **In this demo, everything is public.** That's possible because the data is fictional. In real use, the owner would choose, entry by entry, which headlines are public; everything else would stay as a fingerprint, readable in full only by people the owner authorizes. Anything published on a blockchain is permanent and cannot be removed. This is planned, not shown in this demo.
- **Some shortcuts are deliberate.** An asset's identity can't be updated after registration, only added to with new entries. A replacement is recorded twice, as an entry describing the work and as a change to the equipment list made by the holder, and the contract doesn't link the two, so they could disagree. The entry categories are fixed, so adding one would need a new contract. A provider can't step down on its own; the owner or asset manager has to revoke it.

## Live demo (Polygon Amoy test network)

Both passports were recorded on 19 October 2026 on Polygon Amoy, a public test network where nothing has monetary value. Do not send real funds to this address. A test network can be retired, so a full copy of the record is kept in this repository.

- **Contract:** [`0x024f7b7064ff3f824105563c443fb6db5365bdf2`](https://amoy.polygonscan.com/address/0x024f7b7064ff3f824105563c443fb6db5365bdf2)
- **Outcome:** two passports, Wildrye Solar (AP-0001) in 41 recorded steps and Verrow Solar (AP-0002) in 61, each step a transaction on the network. The final state was checked against both planned histories.
- **Every transaction:** listed in [`deployments/amoy-demo.json`](deployments/amoy-demo.json).
- **Record copy:** [`deployments/`](deployments/) and [`viewer/data/`](viewer/data/).
<!-- PENDING: change to "verified" once source verification on amoy.polygonscan.com is done (D44, never cut). -->
- **Source code on the explorer:** verification pending.

**Simulated recorded dates.** Five years of history were recorded in one day. The passports show simulated recorded dates (2021–2026), taken from a demo-only file, [`deployments/amoy-overlay.json`](deployments/amoy-overlay.json). The explorer shows when each entry was actually written, in October 2026. The dates when events happened are recorded on the network as shown.

**Illustrative details.** A few fields on each passport's data page are illustrative and not recorded on the network: commercial operation date, developer, grid connection, DC capacity and DC/AC ratio, energization, typology and orientation, as well as the modules' performance warranty. Explorer links appear only on recorded items, and each passport's key says which fields are illustrative.

**If the network can't be read.** The passport pages read the live record. If that fails, or takes longer than 12 seconds, they show the copy kept in this repository, with a banner giving the date it was taken.

## Verify a record yourself

You don't need to trust anyone to check that a document matches the record. It takes about five minutes and a command line; the tools are already on your computer, so there's nothing to install. If you'd rather not, skip this section: nothing else in this README depends on it.

<!-- PENDING: confirm step 5 on the live transaction (0x03343efd…cfa147: From = Brennick 0x8c3C…8CE4; fingerprint 775d4f67…daae133 in Input Data, Original view), then test all steps from a fresh clone. -->
1. **Pick a sample file**, for example `demo/evidence/verrow/cableTemp/inspection-report.txt`, from this repository. Download the file (or clone the repository) rather than copying and pasting its text: copying can change invisible characters, such as line endings, and the fingerprint would no longer match.
2. **Fingerprint it** with the tool already on your computer, running the command in the folder that contains the file:
   - Windows (PowerShell): `Get-FileHash -Algorithm SHA256 inspection-report.txt`
   - macOS: `shasum -a 256 inspection-report.txt`
   - Linux: `sha256sum inspection-report.txt`
3. **Compare** the result with the fingerprint listed next to the file in the same folder's `manifest.json`. They should match exactly (upper or lower case doesn't matter).
4. **Fingerprint the manifest** the same way. This single value is what was recorded on the network with the entry.
5. **Look it up** on the block explorer. Find the matching step in `deployments/amoy-demo.json` (the step named `verrow #26`: Brennick O&M's October 2022 temporary repair on cable section C) and open its transaction on the Amoy explorer. In the transaction's Input Data (Original view), search (Ctrl+F) for the fingerprint from step 4, without a leading `0x`. If it appears, that exact document was recorded at that time, by the address shown as "From." (Until the contract's source code is published on the explorer, the fingerprint appears inside the raw Input Data rather than as a labelled field.)

Change one character in the file and repeat step 2: the fingerprint changes completely, and the match fails.

**The passport pages can be checked too.** The published pages come with a `SHA256SUMS` file listing the fingerprint of every file served. Download the files with their subfolders (`lib/`, `data/`) kept as they are, put `SHA256SUMS` in the top folder, and run `sha256sum -c SHA256SUMS` (Linux, or Git Bash on Windows) or `shasum -a 256 -c SHA256SUMS` (macOS). Each file should report OK. In Windows PowerShell there's no single command for this; fingerprint each file with `Get-FileHash` and compare it with its line in the list.

## Get in touch

If you own or manage a solar or storage asset and would like to see what a passport could do for it, write to us. Nothing real goes on this test network; a first step would be a conversation.

**[I am interested in running a pilot with a real asset, no commitments](mailto:support@ontoken.cloud?subject=Asset%20passport%20pilot&body=Name%3A%0ARole%20%28owner%2C%20asset%20manager%2C%20O%26M%20provider%2C%20other%29%3A%0AAsset%20type%20and%20size%20%28optional%29%3A)**

OnToken, LLC receives your message and contact details, and handles them under its privacy policy on [ontoken.cloud](https://ontoken.cloud).

## Technical details

For how it's built, tested and run, including the contract's rules, the tests, the demo script and the passport pages: [docs/TECHNICAL.md](docs/TECHNICAL.md).

The companion project, [om-pilot-contract](https://github.com/omarzanotellius-art/om-pilot-contract), explores maintenance recorded as the work happens, with payment released only once it's on record.

---

Copyright © 2026 OnToken, LLC. Free to use under the [MIT License](LICENSE): anyone may use, copy and adapt it, at their own risk and with no warranty.
