# Seolint — deploy package (BNB Chain mainnet, chainId 56)

Everything the owner needs to deploy the Seolint system from their own wallet.
**Nothing in this package deploys by itself** — open `deploy.html` inside the
OKX / MetaMask app browser, connect the owner wallet, and work through steps
01–07. The page is fully self-contained (bytecode embedded, raw wallet calls,
no CDN scripts).

## Contracts

| File | Contract | What it is |
|---|---|---|
| `LintToken.sol` | `LintToken` | $LINT — ERC-20 + ERC20Burnable |
| `SeolintPass.sol` | `SeolintPass` (SPASS) | Pass NFT — the second Seolint NFT |
| `SeolintScan.sol` | `SeolintScan` (SCAN) | The daily Node NFT + all mint lanes |
| `LintClaim.sol` | `LintClaim` | Claim contract — deploy **3 identical copies** |

Compiled with solc 0.8.20 + OpenZeppelin 4.9.6, optimizer 200 runs, clean
compile (0 errors, 0 warnings). Bytecode + ABI sit next to each source
(`*.bytecode.txt`, `*.abi.json`); recompile any time with `node compile.js`.
Runtime sizes: LINT 2,575 B · SPASS 7,183 B · SCAN 11,956 B · LintClaim 4,143 B
(all far under the 24,576 B limit).

## Locked numbers

- **$LINT**: supply **10,000,000,000**, all minted to the deployer at deploy.
  No mint function, no tax. Claim pool **6,000,000,000 (60%)** = 3 claim
  contracts × 2,000,000,000. The other 4,000,000,000 stays with the deployer.
- **Day**: runs 12:00 UTC → next 12:00 UTC (the seal).
  `dayId = (timestamp − 12h) / 1 day`.
- **Scan cap**: 1,200 per day across all wallets; max 10 per wallet per day
  on the free + paid lanes.
- **Free lane**: 1 per wallet per day, gated on-chain by the Binance Agent ID
  registry `0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F` (`balanceOf > 0`, the
  same check TalvioBNB and VoltaGent use). Global free quota **300 per
  6-hour phase** (absolute buckets aligned to 00/06/12/18 UTC).
- **Paid ladder**: priced by the wallet's count that day — next scan #1–5 =
  **0.0002 BNB**, #6–10 = **0.0004 BNB**. Scan #1 is normally the free one, so
  in the normal flow paid scans are #2–5 and #6–10 exactly as specced.
  Overpayment is refunded.
- **Pass**: **0.00123 BNB**, unlimited supply, anyone can buy with a normal
  wallet, transferable, never expires. Holding one enables the Pass lane:
  1 extra Scan per day with no Agent ID (counted in the daily cap and in the
  wallet's day count).
- **Burn lane**: burn **50,000 LINT** for 1 extra Scan beyond the 10/day max
  (still bound by the 1,200/day cap). The minter must first `approve` the
  Scan contract for ≥ 50,000 LINT; the Scan contract spends it via
  `burnFrom`.
- **Traits**: seed = keccak256(dayId, tokenId, minter). **Royal** if
  seed % 1000 ≥ 970 (~3 in 100). Kind = seed % 3 → Cotton / Wool / Silk.
- **Claims**: open at seal + 6 hours, never expire, one claim per Scan across
  all three claim contracts (the claimed flag lives in the Scan contract).
  Amount by the day's unique participant count: <25 → **2,500** · 25–100 →
  **12,500** · >100 → **60,000** · Royal → **250,000** LINT regardless.
  Fee: **0.000277 BNB** standard, **0.000555 BNB** Royal; overpayment
  refunded; fees withdrawable by each claim contract's owner.

## Deploy order (deploy.html steps)

0. Connect wallet on BNB Chain — the page warns and offers a switch if not,
   and shows the BNB + LINT balances (top up to ~0.02 BNB for the full run:
   6 deploys + ~13 setup transactions).
1. **Deploy LINT** — 10 billion lands in the owner wallet.
2. **Deploy Pass**, then **Open Pass Mint**.
3. **Deploy Scan** (mint stays closed).
4. **Deploy LintClaim ×3** (constructor takes the LINT address).
5. **Wire all** — 8 transactions: Scan ← LINT, Scan ← Pass, Scan authorises
   Claim #1/#2/#3, Claim #1/#2/#3 ← Scan. Safe to re-run if interrupted.
6. **Fund** — 2,000,000,000 LINT to each claim contract.
7. **Set base URI** on Scan (prefilled:
   `https://talvio-io.github.io/Seolint-neww/nft/metadata/`), then
   **Open Scan Mint**.

Afterwards, send all six contract addresses to Muse so the website, the
skill file, and the metadata pipeline can be wired to them.

## Honest notes

- **The arithmetic quiz is off-chain.** Agents ask the question in chat
  before minting (as with Contextgraph / DOTFIELD). The only on-chain free
  gate is the Agent ID registry check — a wallet holding an Agent ID that
  skips the quiz cannot be stopped by the contract.
- **Metadata is not in this package.** Each Scan's `tokenURI` resolves to
  `baseURI + tokenId + ".json"`. The day's globe plate image and one JSON
  per minted Scan (number, kind, Royal flag, claim tier) still have to be
  generated and uploaded per day after mint opens — same pattern as the
  DOTFIELD Founder images/metadata. The three approved samples (Scan Nº 003
  Royal, Scan Nº 042 Wool, Pass Nº 001) live in `~/workspace/seolint-nft/`.
- **Pass metadata**: `SeolintPass` has its own `setBaseURI` (not in the
  console steps — set it the same way if/when Pass metadata is published).
- Deploy gas estimates are shown by the wallet at each confirmation; the
  console's 0.02 BNB guidance is a buffer, not a quote.
