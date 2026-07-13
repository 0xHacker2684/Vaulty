# SwuM Agent 3 Attack Vectors

## AV-1: First depositor + direct donation + zero-share victim deposit

**Candidate:** CAND-001.

**State required:** Empty vault; attacker can become first depositor; attacker can transfer underlying directly to the vault; victim uses `deposit` without a min-shares wrapper.

**Transaction path:**

1. Attacker obtains underlying. In local scope this is free via `VToken.mint(attacker, amount)` at `src/VToken.sol:15-18`.
2. Attacker approves and calls `Vaulty.deposit(1, attacker)` at `src/Vaulty.sol:50-76`.
3. Attacker transfers `D` underlying directly to `address(vaulty)`.
4. Victim approves and calls `Vaulty.deposit(A, victim)`.
5. Victim receives `floor(A * 2 / (D + 2))` shares. If `D >= 2A - 1`, victim receives zero shares.
6. Attacker exits using `redeem` or `withdraw` and captures a share of the victim's deposited assets.

**Why reachable:** `test/Vault.t.sol:24-50` already performs the first three meaningful steps with Bob depositing `1`, transferring `100e18` directly, and Alice depositing `100e18`. The test does not assert balances, but the state path is real and the targeted test passes.

**Existing mitigations that fail:**

- OZ v5 virtual offset exists, but Vaulty bypasses `_convertToShares()` on the first deposit by manually setting `shares = assets`.
- No min-shares/slippage parameter.
- No internal total-assets tracking to exclude donations.
- `deposit` allows `_mint(receiver, 0)` because it only checks `assets > 0`.

## AV-2: Arbitrary burn of vault underlying

**Candidate:** CAND-002.

**State required:** Vault holds any `VToken` balance from user deposits or donations.

**Transaction path:**

1. Victim deposits assets into Vaulty and receives shares.
2. Attacker calls `VToken.burn(address(vaulty), amount)` with `amount <= VToken.balanceOf(address(vaulty))`.
3. Vaulty's inherited `totalAssets()` immediately decreases because it reads raw token balance.
4. Victim redeem/withdraw returns fewer assets or can be made impossible if assets are burned to zero.

**Why reachable:** `VToken.burn` is external and has no owner/minter/burner role check. OpenZeppelin `_burn` only requires the `from` address has enough balance.

**Existing mitigations that fail:** Vaulty has no hook or internal ledger to prevent token-level balance destruction; ERC4626 assumes the asset token itself enforces sane balances.

## AV-3: Pause/toggle bypass

**Candidate:** CAND-003.

**State required:** Owner has called `setDepositsEnabled(false)` or `setWithdrawalsEnabled(false)`.

**Transaction path:**

1. Owner disables deposits or withdrawals.
2. User/attacker calls the corresponding ERC4626 function anyway.
3. Function succeeds because no user flow reads the flag.

**Why reachable:** Setters are owner-only and public getters expose disabled state, but deposit/mint/withdraw/redeem have no flag checks.

**Existing mitigations that fail:** `nonReentrant` and amount checks do not enforce pause state.

## AV-4: Fee bypass / dead fee accounting

**Candidate:** CAND-004.

**State required:** Owner sets a nonzero deposit or withdrawal fee.

**Transaction path:**

1. Owner calls `setDepositFee(newFee)` or `setWithdrawFee(newFee)` with `newFee <= 1000`.
2. User deposits/mints/withdraws/redeems.
3. Full amount is transferred as if fee were zero; `totalFeesCollected` remains zero.
4. `collectFees()` remains unusable because it requires `totalFeesCollected > 0`.

**Why reachable:** Fee variables are never read in the four operational flows; `totalFeesCollected` is never incremented anywhere in `src/`.

**Existing mitigations that fail:** Fee upper bound only constrains storage values, not execution.

## AV-5: Minimum-withdraw bypass through sibling function

**Candidate:** CAND-005.

**State required:** Owner sets `minWithdrawAmount > 1`; user has enough shares to withdraw below the minimum.

**Transaction path:**

1. Owner calls `setMinWithdrawAmount(M)`.
2. User attempts `redeem(sharesWorthLessThanM, ...)`; this reverts at line 141.
3. User calls `withdraw(M - 1, receiver, owner)`; this succeeds because `withdraw` does not check `minWithdrawAmount`.

**Why reachable:** Both exit functions are public ERC4626 siblings over the same share balance and asset pool.

**Existing mitigations that fail:** Allowance checks and `_burn` only verify share authorization, not configured minimum.

## Vectors checked but not promoted

- Reentrancy through token callbacks: no concrete path because the four asset movement functions are `nonReentrant`, and the transfer/mint/burn ordering matches OZ's own ERC4626 `_deposit`/`_withdraw` commentary.
- Oracle/AMM manipulation: no oracle, AMM, lending, or price feed code in `src/`.
- Signature replay: no signatures or permits in `src/`.
- Proxy initialization/storage collision: no upgradeable/proxy implementation in `src/`.
- `collectFees` owner drain: not reachable in current code because `totalFeesCollected` is private and never incremented.
