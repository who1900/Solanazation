# STAKING-CREDITS — MVP contract

## Status and invariant
- Scope: design only; no gameplay/backend implementation and no movement of real funds.
- Pilot LST: JitoSOL on mainnet, mint `J1toso1uCk3RLmjorhTtrVwY9HJ7X8V9yYac6Y7kGCPn`.
- Credits are off-chain gameplay points, nonredeemable, nontransferable, cosmetic-only, and never a claim on SOL/JitoSOL.
- Production earning rate is `DISABLED`; any rate used in dev/test is provisional and must not ship as an economic promise.
- Source of truth is server + Solana finalized state/history; local save, device clock, reconnect count, and client-reported LST balance are untrusted.
- Acceptance invariant: transfer/reconnect/retry/edited save can never multiply credits.

## Asset flow
- Player keeps JitoSOL in the player's own wallet; Solanazation never custodies it in this MVP.
- Direct deposit: SOL enters the Jito stake-pool flow and JitoSOL is minted according to that protocol.
- DEX purchase: existing JitoSOL is bought/transferred from market liquidity; it is not a new stake deposit.
- The game rewards verified holding time of the JitoSOL mint, not deposits, transfers, purchases, staking actions, or reconnects.
- Acquisition/redemption UI and all mainnet fund-moving transactions are out of scope for this milestone.

## Environment separation
- `devnet`: use a Solanazation mock SPL mint/pool with zero real value; never alias it to the mainnet mint.
- `mainnet`: recognize only the configured real JitoSOL mint above; MVP remains read-only toward user funds.
- Cluster and mint are server configuration and are included in every auth/session/ledger record.

## Wallet authentication
- Backend issues a one-time challenge containing protocol version, configured domain, wallet pubkey, cluster, nonce, issued-at, and expiry.
- Android authenticates via MWA message signing; backend verifies the signature against the claimed pubkey.
- Nonce is single-use and server-stored; expired, replayed, wrong-domain, wrong-wallet, or wrong-cluster challenges fail.
- Authentication proves control of the wallet key only; it does not by itself prove historical token ownership.

## Holding-time proof
- Enrollment starts at the first server-observed finalized JitoSOL balance; there is no retroactive credit from a current balance.
- A current balance proves only current ownership. It is insufficient to claim that the balance was held continuously before that observation.
- Backend advances a per-wallet accrual cursor only across intervals whose finalized token-account history can be bridged and reconciled.
- Token-account transfers/decreases split the interval: the sender stops earning for moved units before the receiver can start earning them.
- If RPC history is unavailable, ambiguous, stale, or leaves a monitoring gap, that interval earns zero until continuity is re-established.
- `confirmed` may be shown for UX, but credit settlement uses `finalized` state to avoid crediting state later rolled back.
- A historical indexer is optional for MVP; without one, RPC transaction/signature history must cover every credited interval.
- If only current-balance RPC is available, exact holding time is not provable and production credit accrual must remain disabled.

## Ledger and idempotency
- Ledger is append-only server data; client receives a projection only.
- Each settlement has a deterministic idempotency key from cluster, mint, wallet, interval/cursor, and ruleset version.
- Retry or reconnect returns the existing settlement; it never creates another reward row.
- Server stores last finalized slot/cursor and never settles the same interval twice.
- Credit amount derives from verified token-time under one versioned ruleset, with explicit rounding and caps defined later.
- Wallet-to-wallet movement preserves no bonus: only the wallet holding units during a provable interval accrues for those units.
- A game account may have one reward-eligible wallet at a time; wallet changes require closing the prior accrual cursor first.
- Credits cannot be transferred between game accounts, burned for crypto, redeemed for LST/SOL, or used to mint an on-chain claim.

## Gameplay contract
- Credits unlock cosmetics/status only: skins, banners, profile/validator-city visual variants, titles, or equivalent non-power rewards.
- Credits must not buy combat stats, production speed, research advantage, staking yield, governance weight, or resource multipliers.
- Civ-style economy remains balanced independently from SOL/JitoSOL value and staking yield.

## Next implementation gate
- Before backend code, agree on auth service, database/ledger, RPC provider/history retention, account identity model, and observability.
- Then specify one devnet-only vertical slice: MWA challenge -> mock balance proof -> one idempotent settlement -> cosmetic projection.
- Mainnet recognition stays read-only and production earning stays disabled until rate, abuse model, and operations are approved.
