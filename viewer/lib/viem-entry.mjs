// Entry for the viewer's self-hosted viem bundle (Stage 3A, decision: self-host).
// Only what the viewer needs to READ the chain. Built by scripts/build-viewer-lib.mjs.
export { createPublicClient, http, fallback } from "viem";
export { polygonAmoy, hardhat } from "viem/chains";
