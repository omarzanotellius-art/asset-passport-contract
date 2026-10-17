// Read-only: derives the ten demo wallets from the keystore's recovery phrase (rule S2),
// shows each one's POL balance, and compares them with the addresses created in MetaMask.
// Sends nothing; cannot spend anything.
//
//   npx hardhat run scripts/wallets.ts --network amoy

import { network } from "hardhat";
import { formatEther, getAddress } from "viem";

const WALLETS = ["funder", "larkmoor", "tavren", "tarrow", "halvern", "ostrell", "pellam", "quenby", "brennick", "dalbeck"];
// Created in MetaMask (profile "Passport Pilot Testnet"), 2026-10-18. Public addresses, not secrets.
const EXPECTED = [
  "0x67a5ed1307E32C79B8BBAf2fd78cA44B72Ef281D", "0x3304404E980475544867386015266F84d964A2b7",
  "0x6EFAe8EF125DA09D5041f51fdFD0B68A98B8907a", "0x458c8A863278d574F12e3ebb8738b58bFc78C2bC",
  "0x16Ef78b47B957D0737D3aB4EB977F178e9c0e8D5", "0x3F6d5771A513C8f96aca7Ad30bADbC9D083C1408",
  "0x51846A4C826b054e7aCf49aDeD8c84E3Ed9c6D3c", "0x8788518e283f9246370f5206A5A9acE629F5428f",
  "0x8c3C25E224147Fe547B37222d8E0f25839858CE4", "0x0DE756684AA36B38F1D9c0970E9f1f4c615Bd362",
];

const { viem, networkName } = await network.create();
const publicClient = await viem.getPublicClient();
const clients = await viem.getWalletClients();
const chainId = await publicClient.getChainId();
console.log(`\nNetwork: ${networkName} (chain ${chainId})\n`);

let mismatches = 0;
let total = 0n;
for (let i = 0; i < WALLETS.length; i++) {
  const derived = getAddress(clients[i].account.address);
  const balance = await publicClient.getBalance({ address: derived });
  total += balance;
  const match = chainId === 80002 ? (derived === EXPECTED[i] ? "matches MetaMask" : `DIFFERENT from MetaMask (${EXPECTED[i]})`) : "";
  if (chainId === 80002 && derived !== EXPECTED[i]) mismatches++;
  console.log(`  ${String(i).padStart(2)} ${WALLETS[i].padEnd(9)} ${derived}  ${formatEther(balance).padStart(12)} POL  ${match}`);
}
console.log(`\n  Total: ${formatEther(total)} POL`);
if (chainId === 80002) {
  if (mismatches) {
    console.log(`\n${mismatches} address(es) differ: the keystore phrase is not the MetaMask phrase, or words are out of order.`);
    process.exitCode = 1;
  } else {
    console.log("\nAll ten addresses match MetaMask: the keystore holds the right phrase, in the right order.");
  }
}
