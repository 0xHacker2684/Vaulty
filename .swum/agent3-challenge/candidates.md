# SwuM Agent 3 Candidates

## Candidate Summary

| ID | Title | Primary impact | Affected code | Validation priority |
| --- | --- | --- | --- | --- |
| CAND-001 | First-deposit/direct-donation path can make later deposits mint zero shares | Victim deposit confiscation; drain-capable in local `VToken` scope due free mint | `Vaulty.deposit`, inherited `ERC4626.totalAssets/_convertToShares`, `VToken.mint` | High |
| CAND-002 | Anyone can burn Vaulty's underlying asset balance | User share backing destroyed / withdrawal loss or DoS | `VToken.burn`, inherited `Vaulty.totalAssets` | High |
| CAND-003 | Deposit/withdraw enable toggles are not enforced | Emergency pause bypass / policy bypass | `setDepositsEnabled`, `setWithdrawalsEnabled`, four ERC4626 flows | Medium |
| CAND-004 | Configured fees are never applied or accrued | Fee bypass; `collectFees` dead path | fee setters, four ERC4626 flows, `collectFees` | Medium |
| CAND-005 | `withdraw` bypasses `minWithdrawAmount` enforced by `redeem` | Minimum exit policy bypass / dust griefing | `withdraw`, `redeem`, `setMinWithdrawAmount` | Low/Medium |

## CAND-001: First-deposit/direct-donation path can make later deposits mint zero shares

**Affected contract/function/lines:**

- `src/Vaulty.sol:50-76` (`deposit`).
- `src/Vaulty.sol:62-66` first-deposit branch and later `previewDeposit` use.
- `src/Vaulty.sol:69-71` asset transfer then share mint.
- `lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol:116-118` inherited `totalAssets()`.
- `lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol:225-227` inherited `_convertToShares()`.
- `src/VToken.sol:15-18` unrestricted mint makes donation capital free in local challenge scope.

**Exact assumption challenged:** A positive `assets` deposit always mints an economically fair positive amount of shares, and inherited ERC4626 virtual offset protects the first-depositor donation case.

**Required state and transaction path:**

1. Vault is empty.
2. Attacker calls `VToken.mint(attacker, D + 1)` if using the local challenge asset, then approves Vaulty.
3. Attacker calls `Vaulty.deposit(1, attacker)`. Because `totalSupply() == 0`, Vaulty sets `shares = assets = 1` instead of using `_convertToShares()`.
4. Attacker transfers `D` assets directly to `address(vaulty)`.
5. Victim calls `Vaulty.deposit(A, victim)`.
6. Victim shares are `floor(A * (1 + 1) / (1 + D + 1)) = floor(2A / (D + 2))`.
7. If `D >= 2A - 1`, victim receives `0` shares while `safeTransferFrom` still transfers `A` assets.
8. Attacker exits with `redeem`/`withdraw`; with free local minted donation, attacker can extract victim value from the vault.

**Why the state is reachable:** `test/Vault.t.sol:24-50` already executes the first-deposit/direct-transfer/later-deposit sequence. The targeted local test passes. `VToken.mint` is callable by anyone.

**Violated invariant or unintended behavior:** Share issuance must not let one user confiscate another user's deposit by manipulating raw `totalAssets()` before the deposit. A nonzero deposit should not mint zero shares without explicit user slippage acceptance.

**Attacker benefit or user/protocol loss:** Victim loses all deposited assets for zero shares when parameters satisfy the inequality. In production with costly real USDC donation, this is at minimum a grief/dilution vector and can become profitable over multiple victims or if the attacker can source donation assets cheaply. In this repo's concrete `VToken` scope, donation assets are free due unrestricted mint, making the path drain-capable.

**Why existing mitigations fail:**

- OZ v5 virtual share/asset math is bypassed on the first deposit by Vaulty's manual `shares = assets` branch.
- `deposit` has no min-share/slippage argument and no `require(shares > 0)`.
- `totalAssets()` includes unsolicited transfers.
- `nonReentrant` does not address exchange-rate manipulation across transactions.

**Proof strategy for Agent 4:** Write a Foundry test that:

1. Deploys `VToken` and `Vaulty`.
2. Attacker mints and deposits `1`.
3. Attacker donates `201e18`.
4. Victim deposits `100e18`.
5. Assert `vaulty.balanceOf(victim) == 0` and victim's `VToken` balance decreased by `100e18`.
6. Redeem/withdraw attacker shares and assert attacker receives assets attributable to the victim deposit.

## CAND-002: Anyone can burn Vaulty's underlying asset balance

**Affected contract/function/lines:**

- `src/VToken.sol:20-23` (`burn(address from, uint256 amount)`).
- `lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol:116-118` inherited `totalAssets()`.
- Victim exits through `src/Vaulty.sol:107-150`.

**Exact assumption challenged:** Only authorized owners of underlying tokens can destroy or move them; Vaulty's share accounting remains backed unless users withdraw/redeem or authorized fees are collected.

**Required state and transaction path:**

1. Victim deposits assets into Vaulty and receives shares.
2. Vault's `VToken.balanceOf(address(vaulty))` is positive.
3. Attacker calls `VToken.burn(address(vaulty), amount)`.
4. Vaulty's `totalAssets()` decreases immediately.
5. Victim's later `redeem`/`withdraw` returns less, or if all assets were burned, cannot recover the original deposit.

**Why the state is reachable:** `VToken.burn` is external and has no `onlyOwner`, allowance, or role check. OpenZeppelin `_burn` does not require `msg.sender == from`; it only mutates the supplied account if balance is sufficient.

**Violated invariant or unintended behavior:** Vault shares should represent a claim on underlying unless a corresponding share burn or authorized accounting operation occurs. Here underlying can be destroyed independently of shares.

**Attacker benefit or user/protocol loss:** Direct user loss / permanent vault backing destruction. This is sabotage rather than profit unless combined with other market/external positions, but it is concrete loss in the in-repo asset model.

**Why existing mitigations fail:** Vaulty trusts the asset token. No Vaulty-level guard can prevent the token contract from burning `address(vaulty)` balance after deposits. `ReentrancyGuard` is irrelevant because the attacker calls `VToken` directly.

**Proof strategy for Agent 4:** Foundry test: victim deposits `100e18`; attacker calls `vToken.burn(address(vaulty), 100e18)`; assert `vaulty.totalAssets() == 0`, victim still has shares, and `redeem` returns zero or reverts depending on exact share/assets requested.

## CAND-003: Deposit/withdraw enable toggles are not enforced

**Affected contract/function/lines:**

- `src/Vaulty.sol:181-184` (`setDepositsEnabled`).
- `src/Vaulty.sol:187-190` (`setWithdrawalsEnabled`).
- Missing checks in `deposit` lines 50-76, `mint` lines 79-104, `withdraw` lines 107-126, and `redeem` lines 129-150.

**Exact assumption challenged:** The exposed enabled/disabled state gates user operations.

**Required state and transaction path:**

1. Owner calls `setDepositsEnabled(false)`.
2. Attacker/user calls `deposit` or `mint`; operation succeeds if amount checks pass.
3. Owner calls `setWithdrawalsEnabled(false)`.
4. Attacker/user calls `withdraw` or `redeem`; operation succeeds if share/amount checks pass.

**Why the state is reachable:** Setters are callable by owner, and no operational function reads the flags.

**Violated invariant or unintended behavior:** Emergency or administrative toggle state is not coupled to the functions it names.

**Attacker benefit or user/protocol loss:** Bypass of emergency controls, potentially allowing deposits during intended shutdown or withdrawals during intended freeze. Not a standalone fund drain without a reason the owner toggled the state.

**Why existing mitigations fail:** Amount checks, allowances, and `nonReentrant` do not reference toggle state.

**Proof strategy for Agent 4:** Test owner disables each flag and then assert the corresponding user function still succeeds.

## CAND-004: Configured fees are never applied or accrued

**Affected contract/function/lines:**

- `src/Vaulty.sol:154-165` fee setters.
- `src/Vaulty.sol:50-150` user flows.
- `src/Vaulty.sol:200-206` `collectFees`.

**Exact assumption challenged:** `depositFee`, `withdrawFee`, and `totalFeesCollected` are operationally coupled to vault asset flows.

**Required state and transaction path:**

1. Owner sets `depositFee` or `withdrawFee` to a nonzero value <= `MAX_FEE`.
2. User deposits/mints/withdraws/redeems.
3. User receives the same shares/assets as if the fee were zero.
4. `getTotalFeesCollected()` remains zero and `collectFees()` reverts with `No fees to collect`.

**Why the state is reachable:** Fee variables are only written by setters and read by getters; `totalFeesCollected` is only reset in `collectFees`.

**Violated invariant or unintended behavior:** Configured protocol fees are silently ignored, and fee accounting is dead.

**Attacker benefit or user/protocol loss:** Users avoid intended fees; protocol/fee recipient loses revenue. Not a direct principal drain.

**Why existing mitigations fail:** `MAX_FEE` constrains values but no code applies those values.

**Proof strategy for Agent 4:** Set fees, execute deposit and withdraw, compare results to zero-fee expected values, assert `totalFeesCollected == 0` and `collectFees()` reverts.

## CAND-005: `withdraw` bypasses `minWithdrawAmount` enforced by `redeem`

**Affected contract/function/lines:**

- `src/Vaulty.sol:107-126` (`withdraw`) lacks minimum check.
- `src/Vaulty.sol:129-150` (`redeem`) checks `assets >= minWithdrawAmount` at line 141.
- `src/Vaulty.sol:174-177` (`setMinWithdrawAmount`).

**Exact assumption challenged:** The minimum withdrawal amount applies to all exits.

**Required state and transaction path:**

1. User has shares worth at least `M - 1` assets.
2. Owner calls `setMinWithdrawAmount(M)` where `M > 1`.
3. User calls `withdraw(M - 1, user, user)` and succeeds.
4. A comparable `redeem` returning less than `M` assets would revert.

**Why the state is reachable:** Both functions are public and operate on the same shares/assets; only `redeem` reads the minimum.

**Violated invariant or unintended behavior:** Sibling exit paths enforce different policy for the same economic action.

**Attacker benefit or user/protocol loss:** Bypasses dust/minimum policy and can grief operational assumptions if the minimum was meant to prevent tiny withdrawals.

**Why existing mitigations fail:** `withdraw` only checks `assets > 0` and share authorization.

**Proof strategy for Agent 4:** Set minimum to `10e18`, deposit enough assets, assert `redeem` for shares worth `1e18` reverts but `withdraw(1e18, ...)` succeeds.
