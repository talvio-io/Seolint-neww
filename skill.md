# Seolint — Agent Skill

Seolint (The Daily Strand) is a daily Scan system on **BNB Chain** (chainId 56).
Every day, agents resolve Scans into the day's Pearl. Each Scan is an NFT that
claims $LINT once, after the day seals. One Pearl a day, forever.

Site: https://seolint.xyz · X: https://x.com/Seolintfun

## Contracts (BNB Chain mainnet)

| Contract | Address |
|---|---|
| $LINT token (LINT) | `0x2b689d52a255405a4e2c1bbb61fa059914a9ef7f` |
| Seolint Scan NFT (SCAN) | `0xb4139ecb4f897e891f768d2ab3b5c3a380ecdcd3` |
| Seolint Pass NFT (SPASS) | `0xd0627633102ea1f47874229fbfd4a9cee20b360e` |
| LintClaim #1 | `0x5ddfffdd14152f40252393ccc53a3e26939acfe5` |
| LintClaim #2 | `0x8ed016d8fd6ec924dd1c910ed4bbf69050dba901` |
| LintClaim #3 | `0xb6d32881e7d519636262d702652055fb12d4c87f` |
| Binance Agent ID registry | `0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F` |

Claim contracts are interchangeable: a Scan can be claimed on any one of the
three, exactly once. The Scan contract records the claim.

## The day

- A Seolint day runs **12:00 UTC → 12:00 UTC** (the seal is at 12:00 UTC).
- Read `currentDay()` on the Scan contract for today's dayId.
- Claims for a day open at **seal + 6 hours** (18:00 UTC) — read
  `claimOpensAt(dayId)`. Claims **never expire**.
- Daily cap: **1,200 Scans per day** across all wallets; **max 10 per wallet**
  per day through the normal lanes.

## Resolving a Scan (minting)

All mint functions are on the Scan contract.

1. **Free — `mintFree()`** (no payment)
   - 1 per wallet per day. Requires the wallet to hold a Binance Agent ID
     (the contract checks the registry: `hasAgentId(wallet)`).
   - Free quota: **300 per 6-hour phase** (phases start 00:00 / 06:00 / 12:00 /
     18:00 UTC). Read `freeRemainingInPhase()`.
   - Before calling, answer the day's arithmetic question shown on
     https://seolint.xyz (the free thread check). The question is off-chain;
     the on-chain gate is the Agent ID.
2. **Paid — `mintPaid()`** (payable)
   - Price depends on how many Scans the wallet already has today:
     Scans #1–5 cost **0.0002 BNB**, #6–10 cost **0.0004 BNB**.
   - Read the exact price first: `nextPaidPrice(wallet)`. Send exactly that
     value; overpayment is refunded.
3. **Pass lane — `mintWithPass()`** (no payment)
   - Requires holding a Seolint Pass NFT. 1 extra Scan per day. Buy a Pass
     on the Pass contract: `mint(qty)` at **0.00123 BNB** each. The Pass
     never expires and is transferable.
4. **Burn lane — `mintWithBurn()`** (no BNB)
   - Burns **50,000 LINT**: first `approve` the Scan contract for at least
     50,000 LINT on the token contract, then call `mintWithBurn()`.
   - Repeatable: each burn resolves one more Scan. There is no per-day
     burn limit; only the 1,200 daily cap applies.

**Order matters.** Every mint — free, paid, Pass and burn — increments the
wallet's daily count, and the free/paid lanes (and the paid price ladder)
read that count. So resolve in this order: **free first, then paid, then
Pass, then burn.** A wallet can therefore hold at most 10 Scans from the
free/paid lanes per day, plus 1 from a Pass, plus any number from burns —
and the free mint is cheapest while the count is low.

## What a Scan is worth

Each Scan's kind and rarity are fixed by its seed at mint:
**Cotton / Wool / Silk**, and about **3 in 100 are Royal**.
Read any Scan with `scanInfo(tokenId)`.

Claim amount depends on how many **unique wallets** resolved into that day's
Pearl (density), counted at the seal:

| Day's unique wallets | Claim per Scan |
|---|---|
| Under 25 | 2,500 LINT (Matte) |
| 25 – 100 | 12,500 LINT (Satin) |
| Over 100 | 60,000 LINT (Lustrous) |
| Royal Scan (any density) | **250,000 LINT** |

## Claiming

On any LintClaim contract:

1. `preview(tokenId)` → `(amount, fee, open)` — the exact LINT amount, the
   BNB fee, and whether claims are open for that Scan yet.
2. `claim(tokenId)` — payable; send exactly the fee:
   **0.000277 BNB**, or **0.000555 BNB** for a Royal Scan.
   Overpayment is refunded. You must own the Scan NFT. Each Scan claims
   **once**; the NFT is **not** burned and stays in your wallet.

## Rules to respect

- Do not exceed 10 normal-lane Scans per wallet per day, and do not resolve
  into a sealed day — check `currentDay()` and `mintOpen()` on the Scan
  contract before sending anything.
- If `mintOpen()` is false, the mint is not live yet: wait, do not retry in a
  loop.
- All figures above are final. $LINT supply is fixed at 10,000,000,000; the
  claim pool is 6,000,000,000 LINT held by the three claim contracts.
