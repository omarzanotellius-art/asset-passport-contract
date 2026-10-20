import path from "node:path";
import hardhatToolboxViemPlugin from "@nomicfoundation/hardhat-toolbox-viem";
import { configVariable, defineConfig } from "hardhat/config";

export default defineConfig({
  plugins: [hardhatToolboxViemPlugin],
  solidity: {
    // Compiler: Solidity 0.8.37, taken from the npm "solc" package (pinned in
    // package.json) instead of Hardhat's usual download, as in om-pilot-contract.
    // Everyone who clones this repository compiles with exactly the same compiler file.
    // The path must be absolute, so it is resolved from the project folder.
    version: "0.8.37",
    path: path.resolve("node_modules/solc/soljson.js"),
    // The optimiser makes the compiled code smaller and cheaper to run without
    // changing what it does. All tests run against this optimised code.
    settings: {
      optimizer: { enabled: true, runs: 200 },
    },
  },
  networks: {
    // Polygon Amoy test network (Stage 2 live run). Secrets are referred to by NAME only;
    // their values live in Hardhat's password-protected keystore, never in this file or the
    // repository. All ten wallets come from one recovery phrase, in a fixed order (rule S2):
    // 0 funder, 1 Larkmoor, 2 Tavren, 3 Tarrow, 4 Halvern, 5 Ostrell, 6 Pellam, 7 Quenby,
    // 8 Brennick, 9 Dalbeck.
    amoy: {
      type: "http",
      chainType: "generic",
      chainId: 80002,
      url: configVariable("AMOY_RPC_URL"),
      accounts: { mnemonic: configVariable("AMOY_MNEMONIC"), count: 10 },
    },
  },
  // Source verification on the explorer (amoy.polygonscan.com), via Etherscan's multichain API.
  // The key is referred to by NAME only; its value lives in Hardhat's keystore.
  verify: {
    etherscan: { apiKey: configVariable("ETHERSCAN_API_KEY") },
  },
});
