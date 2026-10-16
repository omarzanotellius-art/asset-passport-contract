# asset-passport-contract

**An asset passport for renewable energy assets: a record of what an asset is and what has happened to it, written by the parties who work on it and kept on a blockchain so nobody can quietly rewrite it.**

> **Status: in development, private.** A learning project. It will run on a public **test** network (Polygon Amoy) with no real money, about two fictional solar farms. It is not a product, service, offering, investment or security token, and it has not been audited.

Companion to [om-pilot-contract](https://github.com/omarzanotellius-art/om-pilot-contract).

## Toolchain

- Hardhat 3.17.0 (viem + Node test runner), Solidity 0.8.37 from npm's `solc` package, forge-std v1.16.2.
- Development runs in GitHub Codespaces (Hardhat does not support Windows on ARM).

```
npm install
npm run build
npm test
```

© 2026 OnToken, LLC. MIT licence (see `LICENSE`).
