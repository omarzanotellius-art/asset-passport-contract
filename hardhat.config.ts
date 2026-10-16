import path from "node:path";
import hardhatToolboxViemPlugin from "@nomicfoundation/hardhat-toolbox-viem";
import { defineConfig } from "hardhat/config";

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
  // The Polygon Amoy network is added in Stage 2, with secrets referred to by name only.
});
