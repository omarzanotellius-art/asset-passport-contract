// Gathers the viewer's data files (Stage 3C, V3) from a finished demo run:
//   viewer/data/config.json       network, contract, block range, explorer
//   viewer/data/abi.json          the contract's interface
//   viewer/data/overlay.json      simulated recorded dates (D51)
//   viewer/data/illustrative.json data-page fields not on the network (D40)
// Read-only: it sends nothing.
//
//   npx hardhat run scripts/viewer-data.ts --network localhost      (testing)
//   npx hardhat run scripts/viewer-data.ts --network amoy           (after the live run)

import { copyFileSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { network } from "hardhat";

const { viem, networkName } = await network.create();
const pc = await viem.getPublicClient();
const state = JSON.parse(readFileSync(`deployments/${networkName}-demo.json`, "utf8"));
const blockOf = async (tx: string) => (await pc.getTransactionReceipt({ hash: tx as `0x${string}` })).blockNumber;
const txs = Object.values(state.done as Record<string, { tx: string }>).map((d) => d.tx);
let toBlock = 0n;
for (const tx of txs) { const b = await blockOf(tx); if (b > toBlock) toBlock = b; }
const fromBlock = await blockOf(state.done["deploy"].tx);
const chainId = await pc.getChainId();

const NETWORKS: Record<number, { name: string; rpc: string[]; explorer: string; mrz: string }> = {
  80002: { name: "Polygon Amoy", rpc: ["https://polygon-amoy-bor-rpc.publicnode.com", "https://rpc-amoy.polygon.technology"],
           explorer: "https://amoy.polygonscan.com", mrz: "AMOY<TESTNET" },
  31337: { name: "a local test chain", rpc: ["http://127.0.0.1:8545"], explorer: "https://amoy.polygonscan.com", mrz: "AMOY<TESTNET" },
};
const n = NETWORKS[chainId];
if (!n) throw new Error(`No viewer settings for chain ${chainId}`);

mkdirSync("viewer/data", { recursive: true });
const config = { chainId, networkName: n.name, rpc: n.rpc, explorer: n.explorer, mrzNetwork: n.mrz,
                 contract: state.contract, fromBlock: fromBlock.toString(), toBlock: toBlock.toString() };
writeFileSync("viewer/data/config.json", JSON.stringify(config, null, 2) + "\n");
writeFileSync("viewer/data/abi.json", JSON.stringify(JSON.parse(readFileSync("artifacts/contracts/AssetPassport.sol/AssetPassport.json", "utf8")).abi) + "\n");
copyFileSync(`deployments/${networkName}-overlay.json`, "viewer/data/overlay.json");
copyFileSync("demo/illustrative.json", "viewer/data/illustrative.json");
console.log(`Viewer data for ${n.name}: contract ${state.contract}, blocks ${fromBlock}–${toBlock}, ${txs.length} transactions.`);
