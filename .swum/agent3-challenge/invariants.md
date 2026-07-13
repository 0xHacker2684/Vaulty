# SwuM Agent 3 Invariant Challenges

## INV-1: Share issuance must match contributed assets

**Intended invariant:** A depositor must not lose deposited assets by receiving zero or economically meaningless shares, except documented ERC4626 rounding dust accepted by the depositor.

**Relevant code:**

- `Vaulty.deposit` lines 57-71.
- Inherited `ERC4626.totalAssets()` lines 116-118 returns the raw underlying balance of the vault.
- Inherited `_convertToShares()` lines 225-227 uses `(assets * (totalSupply + 1)) / (totalAssets + 1)` with floor rounding.

**Challenge:** `deposit` only checks `assets > 0`, not `shares > 0` or a user-supplied minimum. After a first deposit and direct donation, `previewDeposit(assets)` can return zero while `safeTransferFrom` still pulls `assets` from the user and `_mint(receiver, 0)` does not compensate the user.

**Concrete reachable path:**

1. Attacker first deposits `1` asset into an empty vault, receiving `1` share because `Vaulty.deposit` bypasses `_convertToShares()` when `totalSupply() == 0`.
2. Attacker donates `D` assets directly to the vault with `VToken.transfer(address(vaulty), D)`; in the local token, attacker can first mint these assets freely.
3. Victim deposits `A` assets through `deposit(A, victim)`.
4. Since `totalSupply = 1` and `totalAssets = 1 + D`, shares minted are `floor(A * 2 / (D + 2))`.
5. For `D >= 2A - 1`, the victim receives `0` shares while still transferring `A` assets.

**Status:** Violated by CAND-001.

## INV-2: Direct underlying transfers must not confiscate later user deposits

**Intended invariant:** Unsolicited asset transfers should not let an existing share holder determine how many shares a later depositor receives unless the user opted into that exchange rate.

**Relevant code:**

- `Vaulty` does not track internal assets.
- Inherited `totalAssets()` uses `balanceOf(address(this))`.
- `deposit` has no slippage/min-share argument.

**Challenge:** Direct transfers are counted as vault assets before future deposits. This can dilute later deposits into zero/near-zero shares. OZ comments warn this is a donation/inflation risk; Vaulty's custom first-deposit branch makes the initial share supply exactly attacker-controlled.

**Status:** Violated by CAND-001; grief-only or multi-victim costly in a production asset, drain-capable in local scope because `VToken.mint` makes donation capital free.

## INV-3: Vault share supply and underlying balance must remain coupled

**Intended invariant:** A decrease in vault-held underlying should correspond to a burn/redeem of shares, fee collection, or another authorized accounting path.

**Relevant code:**

- `VToken.burn` lines 20-23 allows any caller to burn from any address.
- `Vaulty.totalAssets()` is inherited and reads current vault token balance.

**Challenge:** An attacker can burn the vault's underlying balance directly from the token contract without burning Vaulty shares. Vaulty has no internal accounting that would reject or reconcile this. Users' shares remain outstanding but are backed by fewer or zero assets.

**Status:** Violated by CAND-002.

## INV-4: Pause/enable flags must gate the operations they describe

**Intended invariant:** If `depositsEnabled` or `withdrawalsEnabled` is externally exposed as the enable state, setting it false should stop the corresponding flow.

**Relevant code:**

- `setDepositsEnabled` lines 181-184 writes `depositsEnabled`.
- `setWithdrawalsEnabled` lines 187-190 writes `withdrawalsEnabled`.
- `deposit`, `mint`, `withdraw`, and `redeem` never read either flag.

**Challenge:** The owner can emit a toggle event and getters return disabled, yet attackers/users can still deposit, mint, withdraw, and redeem.

**Status:** Violated by CAND-003. This is not a direct drain by itself, but it invalidates emergency-control assumptions.

## INV-5: Configured fees must be coupled to asset flows and fee accounting

**Intended invariant:** If `depositFee`/`withdrawFee` are configured and exposed, operations should either apply them or explicitly document them as inactive; `totalFeesCollected` should increase when fees are charged.

**Relevant code:**

- Fee setters lines 154-165.
- User flows lines 50-150.
- `collectFees` lines 200-206.

**Challenge:** Deposit and withdrawal functions transfer full user assets or full requested assets without subtracting fees, and no operation increments `totalFeesCollected`. Any user can avoid configured fees; owner cannot collect fees through the advertised accounting path.

**Status:** Violated by CAND-004. Economic impact is fee bypass rather than principal theft.

## INV-6: Withdraw and redeem should enforce equivalent exit policy

**Intended invariant:** If the protocol defines `minWithdrawAmount`, both asset-denominated and share-denominated exits should enforce it consistently.

**Relevant code:**

- `withdraw` lines 107-126 has no `minWithdrawAmount` check.
- `redeem` lines 129-150 checks `assets >= minWithdrawAmount`.

**Challenge:** A user can bypass the minimum by calling `withdraw(minWithdrawAmount - 1, ...)` while `redeem` of shares worth the same amount reverts.

**Status:** Violated by CAND-005. Lower impact unless the minimum is meant to prevent dust griefing or operational cost abuse.

## INV-7: Max deposit limit must match its intended unit

**Intended invariant:** A `maxDepositLimit` should clearly mean per-transaction maximum or per-user/aggregate cap.

**Relevant code:**

- `deposit` line 58 and `mint` line 95 require only the current call's `assets <= maxDepositLimit`.

**Challenge:** If downstream intent treats this as a cumulative deposit cap, an attacker can split deposits into many transactions. No current code or docs prove cumulative intent, so this remains a design assumption for Agent 4, not a primary candidate.

**Status:** Not promoted as a candidate without stronger intent evidence.

## INV-8: Reentrancy guard and ordering must leave state valid at callbacks

**Relevant code:**

- `deposit`/`mint` are `nonReentrant`, transfer before mint.
- `withdraw`/`redeem` are `nonReentrant`, burn before transfer.

**Challenge result:** No concrete reentrancy candidate found in `src/`. Ordering matches OZ's ERC777 commentary for deposit/withdraw flows, and `nonReentrant` blocks direct reentry into the guarded functions.
