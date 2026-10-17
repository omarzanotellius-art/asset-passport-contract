# Passport viewer

The public viewer for the asset passport demo, written and tested here and **copied to the blog repository** (`the_unlisted_brief`, folder `passport/`) for each publication. Spec v1.7, Stage 3.

## `lib/` — the self-hosted viem bundle

The viewer reads the chain with **viem 2.56.8** — the exact version pinned in `package-lock.json`, used by the contract's tests and the demo script. It is bundled into one file and **hosted with the viewer**, so visitors run the same bytes we tested, with no third-party CDN at view time.

| File | |
|---|---|
| `lib/viem-entry.mjs` | What the bundle contains: only what's needed to read the chain (`createPublicClient`, `http`, `fallback`, the Amoy and local chain definitions) |
| `lib/viem-2.56.8.js` | The bundle (327,521 bytes) |

**Fingerprint (SHA-256) of `lib/viem-2.56.8.js`:**
`4e2568fa81f950aecec6d50ebdeacde26b16e9365f367af196619885727133be`

### Rebuild and verify

```
node scripts/build-viewer-lib.mjs
```

The build is reproducible: it prints the file's size and SHA-256, which must match the values above. If a future viem upgrade changes the lock file, rebuild, re-test, and update both values here.
