// Asset passport demo: replays both fictional farms from demo/*.actions.json (spec v1.6;
// Stage 2 part C, rules S1-S11). Pattern taken from om-pilot-contract's scripts/demo.ts.
//
//   Local rehearsal:  npx hardhat run scripts/demo.ts
//       In-process chain, built-in test accounts, nothing saved. Measures gas per wallet.
//   Resume rehearsal: npx hardhat node                (second terminal), then
//                     DEMO_INTERRUPT_AT=<step> npx hardhat run scripts/demo.ts --network localhost
//       stops right after SENDING that step's transaction; re-run without it to resume.
//       Progress: deployments/localhost-demo.json.
//   Live on Amoy:     npx hardhat run scripts/demo.ts --network amoy
//       RESUMABLE: progress saved after every step to deployments/amoy-demo.json.
//
// Step names: "deploy", "topup <wallet>", "wildrye #<n>", "verrow #<n>" (n = action number).
// All names are fictional.

import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { network } from "hardhat";
import { decodeEventLog, formatEther, formatUnits, parseEther, parseGwei } from "viem";

const EXPLORER = "https://amoy.polygonscan.com";
// S7: Polygon refuses tips below 25 gwei; the network's own suggestion has reached 600 gwei.
const TIP = parseGwei("30");

// S2: wallet positions in the recovery phrase (locally: the built-in test accounts)
const WALLETS = ["funder", "larkmoor", "tavren", "tarrow", "halvern", "ostrell", "pellam", "quenby", "brennick", "dalbeck"] as const;
type WalletName = (typeof WALLETS)[number];
const FARMS = ["wildrye", "verrow"] as const;
type Farm = (typeof FARMS)[number];

// S3/S8: gas per wallet MEASURED in the local rehearsal; filled in after it (rounded up).
// The live run refuses to start while these are missing.
// Local rehearsal 2026-10-16 (funder also pays the 9 top-ups on Amoy: + 9 x 21,000).
const MEASURED_GAS: Partial<Record<WalletName, bigint>> = {
  funder: 4_500_000n,   // measured 4,209,764 (deploy) + top-ups
  larkmoor: 4_700_000n, // 4,672,684
  tavren: 550_000n,     // 541,285
  tarrow: 1_000_000n,   // 976,073
  halvern: 5_100_000n,  // 5,044,480
  ostrell: 1_250_000n,  // 1,207,861
  pellam: 210_000n,     // 203,193
  quenby: 210_000n,     // 203,193
  brennick: 1_300_000n, // 1,269,021
  dalbeck: 520_000n,    // 505,285
};

// ---- data -----------------------------------------------------------------------------
type Action = { n: number; date: string; by: WalletName; do: string; [k: string]: any };
const actions: Record<Farm, Action[]> = {
  wildrye: JSON.parse(readFileSync("demo/wildrye.actions.json", "utf8")).actions,
  verrow: JSON.parse(readFileSync("demo/verrow.actions.json", "utf8")).actions,
};

/** "YYYY-MM" or "YYYY-MM-DD" -> unix seconds at 12:00 UTC. */
function ts(date: string): bigint {
  const [y, m, d] = date.split("-").map(Number);
  return BigInt(Date.UTC(y, m - 1, d ?? 1, 12) / 1000);
}
const sha256hex = (b: Buffer | string) => `0x${createHash("sha256").update(b).digest("hex")}` as `0x${string}`;
/** On-chain fingerprint of a document set = SHA-256 of its manifest.json (as in om-pilot-contract). */
const manifestFingerprint = (folder: string) => sha256hex(readFileSync(`demo/evidence/${folder}/manifest.json`));
const ZERO32 = `0x${"0".repeat(64)}` as `0x${string}`;
const ROLE = { AssetManager: 1, OmProvider: 2 } as const;

// Who holds each farm at each action (needed to know whether an entry carries text or a fingerprint).
const holderAt: Record<Farm, WalletName[]> = { wildrye: [], verrow: [] };
for (const farm of FARMS) {
  let holder: WalletName | undefined;
  for (const a of actions[farm]) {
    if (a.do === "registerAsset") holder = a.by;
    holderAt[farm][a.n] = holder!;
    if (a.do === "acceptTransfer") holder = a.by;
  }
}

// ---- connection -------------------------------------------------------------------------
const connection = await network.create();
const { viem, networkName } = connection;
const publicClient = await viem.getPublicClient();
const clients = await viem.getWalletClients();
if (clients.length < WALLETS.length) throw new Error(`Need ${WALLETS.length} accounts, found ${clients.length}.`);
const wallet = Object.fromEntries(WALLETS.map((w, i) => [w, clients[i]])) as Record<WalletName, (typeof clients)[number]>;
const address = (w: WalletName) => wallet[w].account.address;
const chainId = await publicClient.getChainId();
const localChain = chainId === 31337;
const onAmoy = chainId === 80002;
const persist = networkName !== "default";
const STATE_FILE = `deployments/${networkName}-demo.json`;
const OVERLAY_FILE = `deployments/${networkName}-overlay.json`;
const link = (tx: string) => (onAmoy ? `${EXPLORER}/tx/${tx}` : tx);

console.log(`\nAsset passport demo — network: ${networkName}${localChain ? " (local)" : " (LIVE)"}`);
for (const w of WALLETS) console.log(`  ${w.padEnd(9)} ${address(w)}`);

// ---- S6: no placeholders on live networks --------------------------------------------------
if (!localChain) {
  const found: string[] = [];
  for (const farm of FARMS) {
    for (const a of actions[farm]) {
      const text = JSON.stringify({ ...a, date: undefined });
      if (/\[[^\]]+\]/.test(text)) found.push(`${farm} #${a.n}`);
    }
  }
  if (found.length) throw new Error(`Not started — nothing spent. Placeholders still present in: ${found.join(", ")}.`);
}

// ---- S4: progress state ---------------------------------------------------------------------
type Done = { tx: string; at: string; from: string; gas: string; simulated?: string };
type State = {
  contract?: `0x${string}`;
  ids: Record<Farm, { asset?: string; entries: Record<string, string>; units: Record<string, string> }>;
  done: Record<string, Done>;
  pending?: { step: string; tx: `0x${string}` };
};
const state: State =
  persist && existsSync(STATE_FILE)
    ? JSON.parse(readFileSync(STATE_FILE, "utf8"))
    : { ids: { wildrye: { entries: {}, units: {} }, verrow: { entries: {}, units: {} } }, done: {} };
function save() {
  if (!persist) return;
  mkdirSync("deployments", { recursive: true });
  writeFileSync(STATE_FILE, JSON.stringify(state, null, 2) + "\n");
}
if (persist && Object.keys(state.done).length > 0) console.log(`\nResuming: ${Object.keys(state.done).length} steps already done.`);

async function fees() {
  const base = (await publicClient.getBlock()).baseFeePerGas ?? 0n;
  return { maxPriorityFeePerGas: TIP, maxFeePerGas: base * 2n + TIP };
}

/** Runs one transaction step once; if interrupted after sending, waits for that same transaction. */
async function step(name: string, simulated: string | undefined, send: () => Promise<`0x${string}`>,
                    after?: (logs: readonly any[]) => void) {
  if (state.done[name]) return;
  let tx: `0x${string}`;
  if (state.pending?.step === name) {
    tx = state.pending.tx;
    console.log(`… ${name}: waiting for the transaction sent before the interruption`);
  } else {
    tx = await send();
    state.pending = { step: name, tx };
    save();
    if (process.env.DEMO_INTERRUPT_AT === name) {
      console.log(`⚡ interrupted on purpose right after sending "${name}" (rehearsal). Re-run to resume.`);
      process.exit(0);
    }
  }
  const receipt = await publicClient.waitForTransactionReceipt({ hash: tx });
  if (receipt.status !== "success") throw new Error(`${name}: transaction failed (${link(tx)})`);
  after?.(receipt.logs);
  state.done[name] = { tx, at: new Date().toISOString(), from: receipt.from, gas: receipt.gasUsed.toString(), simulated };
  delete state.pending;
  save();
  console.log(`✓ ${name}${simulated ? ` [${simulated}]` : ""}   ${link(tx)}`);
}

// ---- deploy -------------------------------------------------------------------------------------
await step("deploy", undefined, async () => {
  const { deploymentTransaction } = await viem.sendDeploymentTransaction("AssetPassport", [], {
    account: wallet.funder.account, ...(await fees()),
  });
  return deploymentTransaction.hash;
});
if (!state.contract) {
  const receipt = await publicClient.getTransactionReceipt({ hash: state.done["deploy"].tx as `0x${string}` });
  state.contract = receipt.contractAddress!;
  save();
}
const c = await viem.getContractAt("AssetPassport", state.contract!);
const abi = c.abi;
console.log(`  contract: ${onAmoy ? `${EXPLORER}/address/${state.contract}` : state.contract}`);

/** Reads the numbers the contract assigned, from the transaction's events. */
function captureIds(farm: Farm, a: Action) {
  return (logs: readonly any[]) => {
    for (const log of logs) {
      let ev: any;
      try { ev = decodeEventLog({ abi, data: log.data, topics: log.topics }); } catch { continue; }
      if (ev.eventName === "AssetRegistered") state.ids[farm].asset = ev.args.assetId.toString();
      if (ev.eventName === "EntrySubmitted" && a.key) state.ids[farm].entries[a.key] = ev.args.entryId.toString();
      if (ev.eventName === "UnitAdded") {
        const key = a.do === "replaceUnit" ? a.new.key : a.unit.key;
        state.ids[farm].units[key] = ev.args.unitId.toString();
      }
    }
  };
}

// ---- S3/S8: pre-flight and top-ups (live networks only) -------------------------------------------
if (!localChain) {
  const parties = WALLETS.filter((w) => w !== "funder");
  const missing = WALLETS.filter((w) => MEASURED_GAS[w] === undefined);
  if (missing.length) throw new Error(`Not started — measured gas missing for: ${missing.join(", ")}. Run the local rehearsal first.`);
  const maxFee = (await fees()).maxFeePerGas;
  const need = (w: WalletName) => (MEASURED_GAS[w]! * maxFee * 12n) / 10n; // +20%
  if (!state.done["topup " + parties[parties.length - 1]]) {
    let total = need("funder");
    for (const w of parties) {
      const bal = await publicClient.getBalance({ address: address(w) });
      if (bal < need(w)) total += need(w) - bal + parseEther("0.001");
    }
    const funderBal = await publicClient.getBalance({ address: address("funder") });
    console.log(`\nMax fee per gas: ${formatUnits(maxFee, 9)} gwei. Funder holds ${formatEther(funderBal)} POL; needs ~${formatEther(total)}.`);
    if (funderBal < total) throw new Error(`Not started — nothing more spent. Funder needs ${formatEther(total - funderBal)} more POL.`);
  }
  for (const w of parties) {
    await step(`topup ${w}`, undefined, async () => {
      const bal = await publicClient.getBalance({ address: address(w) });
      const value = bal >= need(w) ? 0n : need(w) - bal + parseEther("0.001");
      return wallet.funder.sendTransaction({ to: address(w), value, ...(await fees()) });
    });
  }
}

// ---- S1: play both farms -----------------------------------------------------------------------------
function unitInput(u: any) {
  return {
    name: u.name, system: u.system, oem: u.oem, model: u.model, rating: u.rating, quantity: u.quantity,
    inService: ts(u.inService), isPart: u.isPart, warrantyStart: ts(u.warrantyStart), warrantyEnd: ts(u.warrantyEnd),
  };
}

for (const farm of FARMS) {
  console.log(`\n— ${farm} —`);
  const headlineOf: Record<string, string> = {};
  for (const a of actions[farm]) if (a.do === "submitEntry") headlineOf[a.key] = a.headline;
  for (const a of actions[farm]) {
    const name = `${farm} #${a.n}`;
    const as = async () => ({ account: wallet[a.by].account, ...(await fees()) });
    const asset = () => BigInt(state.ids[farm].asset!);
    const unitId = (key: string) => BigInt(state.ids[farm].units[key]);
    const entryId = (key: string) => BigInt(state.ids[farm].entries[key]);
    const send = async (): Promise<`0x${string}`> => {
      switch (a.do) {
        case "registerAsset":   return c.write.registerAsset([a.identity], await as());
        case "inviteRole":      return c.write.inviteRole([asset(), address(a.wallet), ROLE[a.role as keyof typeof ROLE], a.company], await as());
        case "acceptRole":      return c.write.acceptRole([asset()], await as());
        case "revokeRole":      return c.write.revokeRole([asset(), address(a.wallet)], await as());
        case "addUnit":         return c.write.addUnit([asset(), unitInput(a.unit)], await as());
        case "replaceUnit":     return c.write.replaceUnit([asset(), unitId(a.unit), unitInput(a.new), ts(a.replacedAt)], await as());
        case "extendWarranty":  return c.write.extendWarranty([asset(), unitId(a.unit), ts(a.newEnd)], await as());
        case "proposeTransfer": return c.write.proposeTransfer([asset(), address(a.to)], await as());
        case "acceptTransfer":  return c.write.acceptTransfer([asset()], await as());
        case "confirmEntry":    return c.write.confirmEntry([asset(), entryId(a.entry), headlineOf[a.entry]], await as());
        case "submitEntry": {
          const holderEntry = holderAt[farm][a.n] === a.by;
          return c.write.submitEntry([asset(), {
            category: a.category,
            eventDate: ts(a.eventDate),
            headlineFingerprint: holderEntry ? ZERO32 : sha256hex(a.headline),
            headline: holderEntry ? a.headline : "",
            manifest: a.evidence ? manifestFingerprint(a.evidence) : ZERO32,
            equipmentRef: a.equipmentRef,
            link: a.link ? entryId(a.link) : 0n,
          }], await as());
        }
      }
      throw new Error(`${name}: unknown action ${a.do}`);
    };
    await step(name, a.date, send, captureIds(farm, a));
  }
}

// ---- S10: self-check — the chain must show the end state the action files describe ---------------------
const problems: string[] = [];
for (const farm of FARMS) {
  const list = actions[farm];
  const asset = BigInt(state.ids[farm].asset!);
  const finalHolder = holderAt[farm][list.length];
  const lastHolder = list.at(-1)!.do === "acceptTransfer" ? list.at(-1)!.by : finalHolder;
  if ((await c.read.holderOf([asset])).toLowerCase() !== address(lastHolder).toLowerCase()) problems.push(`${farm}: holder is not ${lastHolder}`);
  const active = new Set<WalletName>();
  for (const a of list) {
    if (a.do === "acceptRole") active.add(a.by);
    if (a.do === "revokeRole") active.delete(a.wallet);
  }
  for (const w of WALLETS.filter((x) => x !== "funder")) {
    const [, status] = await c.read.roleOf([asset, address(w)]);
    if ((status === 2) !== active.has(w)) problems.push(`${farm}: ${w} should ${active.has(w) ? "" : "not "}be active`);
  }
  const submitted = list.filter((a) => a.do === "submitEntry");
  const confirmed = new Set(list.filter((a) => a.do === "confirmEntry").map((a) => a.entry));
  const expectPending = submitted.filter((a) => holderAt[farm][a.n] !== a.by && !confirmed.has(a.key)).map((a) => a.key);
  if ((await c.read.entryCount([asset])) !== BigInt(submitted.length)) problems.push(`${farm}: entry count`);
  const units = list.filter((a) => a.do === "addUnit" || a.do === "replaceUnit").length;
  if ((await c.read.unitCount([asset])) !== BigInt(units)) problems.push(`${farm}: unit count`);
  const pendingOnChain: string[] = [];
  for (const [key, id] of Object.entries(state.ids[farm].entries)) {
    const e = await c.read.getEntry([asset, BigInt(id)]);
    if (!e.confirmed) pendingOnChain.push(key);
    const a = submitted.find((x) => x.key === key)!;
    if (e.confirmed && e.headline !== a.headline) problems.push(`${farm}: headline of ${key}`);
    if (e.eventDate !== ts(a.eventDate)) problems.push(`${farm}: event date of ${key}`);
    if (e.equipmentRef !== a.equipmentRef) problems.push(`${farm}: equipment reference of ${key}`);
    if (e.manifest !== (a.evidence ? manifestFingerprint(a.evidence) : ZERO32)) problems.push(`${farm}: document fingerprint of ${key}`);
    if (e.link !== (a.link ? BigInt(state.ids[farm].entries[a.link]) : 0n)) problems.push(`${farm}: link of ${key}`);
    if (e.author.toLowerCase() !== address(a.by).toLowerCase()) problems.push(`${farm}: author of ${key}`);
  }
  if (pendingOnChain.sort().join() !== expectPending.sort().join()) problems.push(`${farm}: pending entries ${pendingOnChain} ≠ ${expectPending}`);
  console.log(`\n${farm}: AP-000${asset} holder ${lastHolder}, ${submitted.length} entries (pending: ${pendingOnChain.join(", ") || "none"}), ${units} units`);
}

// ---- S5: overlay — simulated recorded dates for every transaction ------------------------------------
const overlay = {
  note: "Demo only (D51): simulated recorded dates for display. The chain's own timestamps are the real ones.",
  chainId, contract: state.contract,
  assets: Object.fromEntries(FARMS.map((f) => [f, state.ids[f].asset])),
  transactions: Object.fromEntries(Object.values(state.done).filter((d) => d.simulated).map((d) => [d.tx, d.simulated])),
};
if (persist) writeFileSync(OVERLAY_FILE, JSON.stringify(overlay, null, 2) + "\n");

// ---- summary: gas per wallet (the figures for MEASURED_GAS) ---------------------------------------------
console.log("\nGas used per wallet:");
for (const w of WALLETS) {
  const g = Object.values(state.done).filter((d) => d.from.toLowerCase() === address(w).toLowerCase())
    .reduce((t, d) => t + BigInt(d.gas), 0n);
  console.log(`  ${w.padEnd(9)} ${g}`);
}
if (persist) console.log(`Progress: ${STATE_FILE}   Overlay: ${OVERLAY_FILE}`);
if (problems.length) {
  console.log(`\nSELF-CHECK FAILED:\n  ${problems.join("\n  ")}`);
  process.exitCode = 1;
} else {
  console.log("\nSelf-check passed: the chain matches the action files.\nDemo complete.\n");
}
