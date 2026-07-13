# SwuM Agent 3 Handoff to Agent 4

Agent 4 must validate the candidates below before writing final reports. Do not treat lower-impact consistency issues as fund drains unless validation finds a concrete loss path beyond the one described.

## Validation context

- Core source: `src/Vaulty.sol`, `src/VToken.sol`.
- Relevant inherited math: `lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol` lines 116-118 and 225-233.
- Local targeted test `forge test --match-path test/Vault.t.sol -vvv` passes.
- Full `forge test -vvv` fails only because `test/Exploit.t.sol` calls hardcoded non-contract address `0x841ECE2d146eaD8724444e2BDA9594D4Ac0398Cc`; do not use that failure as evidence against the local vault path.

## CAND-001: First-deposit/direct-donation path can make later deposits mint zero shares

**Affected contract/function:** `Vaulty.deposit(uint256,address)` at `src/Vaulty.sol:50-76`; inherited `ERC4626.totalAssets()` at OZ `ERC4626.sol:116-118`; inherited `_convertToShares()` at OZ `ERC4626.sol:225-227`; `VToken.mint` at `src/VToken.sol:15-18` for local free donation capital.

**Exact assumption challenged:** A nonzero deposit always gets a fair nonzero share amount, and OZ virtual assets/shares protect against first-depositor donation manipulation.

**Required state and transaction path:**

1. Empty vault.
2. Attacker mints local `VToken` to self, approves Vaulty, and calls `deposit(1, attacker)`.
3. Vaulty mints exactly `1` share because line 62 takes the `totalSupply() == 0` branch and line 63 sets `shares = assets`.
4. Attacker transfers `D` `VToken` directly to `address(vaulty)`.
5. Victim calls `deposit(A, victim)`.
6. `previewDeposit(A)` computes `floor(A * (totalSupply + 1) / (totalAssets + 1)) = floor(2A / (D + 2))`.
7. With `D >= 2A - 1`, victim gets zero shares; line 69 still transfers `A` assets, and line 71 mints zero shares.
8. Attacker exits with their share via `redeem`/`withdraw`, capturing value from victim's deposit. In local scope, the attacker's donation was free because `VToken.mint` is unrestricted.

**Why the state is reachable:** `test/Vault.t.sol:24-50` performs Bob first deposit -> direct transfer to vault -> Alice deposit. The local test passes. `VToken.mint` is unrestricted, so funding the donation is reachable without pre-owned assets.

**Violated invariant or unintended behavior:** Share issuance is not coupled to contributed assets under donation-skewed raw `totalAssets()`. A positive deposit can mint zero shares.

**Attacker benefit or user/protocol loss:** Victim loses deposited assets for zero shares. In local `VToken` scope, attacker can turn free minted donation assets into a claim over victim deposits. If Agent 4 treats production USDC as non-mintable and donation as costly, validate profitability separately; the zero-share confiscation/loss remains reachable, but single-victim ROI may be negative because OZ virtual share captures part of the donation.

**Why existing mitigations fail:** Vaulty bypasses OZ `_convertToShares()` only for the first deposit; no `shares > 0` check; no slippage/min-shares parameter; no internal asset accounting excluding direct donations; `nonReentrant` does not prevent prior-transaction donation.

**Proof strategy:** Add a Foundry test using concrete values `A = 100e18`, `D = 201e18`. Assert victim balance drops by `A`, `vaulty.balanceOf(victim) == 0`, and attacker can withdraw/redeem assets after victim deposit. Also test whether `deposit` emits a zero-share `Deposit` event if useful for reporting.

## CAND-002: Anyone can burn Vaulty's underlying asset balance

**Affected contract/function:** `VToken.burn(address,uint256)` at `src/VToken.sol:20-23`; victim exits in `Vaulty.withdraw`/`redeem` at `src/Vaulty.sol:107-150`; inherited `totalAssets()` at OZ `ERC4626.sol:116-118`.

**Exact assumption challenged:** Vault-held underlying can only decrease through authorized vault flows that also burn shares or account fees.

**Required state and transaction path:**

1. Victim deposits into Vaulty, increasing `VToken.balanceOf(address(vaulty))` and receiving shares.
2. Attacker calls `VToken.burn(address(vaulty), amount)` for any amount up to the vault's token balance.
3. Token balance of Vaulty decreases; Vaulty share supply remains unchanged.
4. Victim later redeems/withdraws against a reduced or empty asset pool.

**Why the state is reachable:** `VToken.burn` is external, unrestricted, and takes an arbitrary `from` address. OpenZeppelin `_burn` only checks that `from` is not zero and has enough balance.

**Violated invariant or unintended behavior:** Underlying backing can be destroyed without burning shares, causing share/asset desynchronization.

**Attacker benefit or user/protocol loss:** User/protocol loss through destruction of backing; permanent withdrawal loss/DoS. Not necessarily direct attacker profit unless combined with external positions, but it is concrete loss in the repo's asset model.

**Why existing mitigations fail:** Vaulty trusts `asset()` and has no internal accounting or permission over token-level burns. `nonReentrant` does not apply because the attacker calls the token directly.

**Proof strategy:** Foundry test: victim deposits `100e18`; attacker calls `vToken.burn(address(vaulty), 100e18)`; assert `vToken.balanceOf(address(vaulty)) == 0`, `vaulty.totalAssets() == 0`, victim still has shares, and redeem/withdraw cannot recover the original assets.

## CAND-003: Deposit/withdraw enable toggles are not enforced

**Affected contract/function:** `setDepositsEnabled` at `src/Vaulty.sol:181-184`, `setWithdrawalsEnabled` at `src/Vaulty.sol:187-190`; missing checks in `deposit`, `mint`, `withdraw`, and `redeem`.

**Exact assumption challenged:** The flags returned by `areDepositsEnabled()` and `areWithdrawalsEnabled()` control whether deposits and withdrawals can occur.

**Required state and transaction path:** Owner disables deposits/withdrawals, then a user calls the disabled operation successfully.

**Why the state is reachable:** The flags are private state but no operational function reads them.

**Violated invariant or unintended behavior:** Administrative enable state is decoupled from asset movement.

**Attacker benefit or user/protocol loss:** Emergency pause bypass or policy bypass. Severity depends on whether docs/UX promise these toggles as safety controls.

**Why existing mitigations fail:** Only amount and allowance checks are enforced; toggle state is ignored.

**Proof strategy:** Test `setDepositsEnabled(false)` then successful `deposit`; test `setWithdrawalsEnabled(false)` then successful `withdraw`/`redeem`.

## CAND-004: Configured fees are never applied or accrued

**Affected contract/function:** `setDepositFee`/`setWithdrawFee` at `src/Vaulty.sol:154-165`; four user flows at `src/Vaulty.sol:50-150`; `collectFees` at `src/Vaulty.sol:200-206`.

**Exact assumption challenged:** Deposit and withdrawal fees affect transfers/shares and accumulate in `totalFeesCollected`.

**Required state and transaction path:** Owner sets nonzero fees; users deposit or withdraw; no fee is deducted or accrued; `collectFees` remains unusable.

**Why the state is reachable:** Fee variables are not read in operational flows; grep found no increment to `totalFeesCollected` anywhere in `src/`.

**Violated invariant or unintended behavior:** Fee state is dead and uncoupled from value movement.

**Attacker benefit or user/protocol loss:** Users bypass intended protocol fees; fee recipient/protocol revenue loss.

**Why existing mitigations fail:** `MAX_FEE` only limits configured values. It does not apply them.

**Proof strategy:** Set `depositFee` and `withdrawFee`; compare actual shares/assets and `totalFeesCollected` against expected fee-charging behavior. Confirm `collectFees()` reverts with `No fees to collect` after fee-bearing operations.

## CAND-005: `withdraw` bypasses `minWithdrawAmount` enforced by `redeem`

**Affected contract/function:** `withdraw` at `src/Vaulty.sol:107-126`, `redeem` at `src/Vaulty.sol:129-150`, `setMinWithdrawAmount` at `src/Vaulty.sol:174-177`.

**Exact assumption challenged:** The configured minimum withdrawal applies to all asset exits.

**Required state and transaction path:** User has shares; owner sets `minWithdrawAmount = M`; user calls `withdraw(M - 1, ...)` and succeeds although equivalent `redeem` below `M` reverts.

**Why the state is reachable:** `withdraw` and `redeem` are public siblings; only `redeem` checks `minWithdrawAmount`.

**Violated invariant or unintended behavior:** Exit policy differs by interface path for the same economic action.

**Attacker benefit or user/protocol loss:** Bypass of minimum withdrawal/dust policy; possible operational griefing if the minimum protects against small transfers.

**Why existing mitigations fail:** `withdraw` checks only `assets > 0`, allowance, and burnability.

**Proof strategy:** Set minimum to `10e18`; deposit `100e18`; assert `withdraw(1e18, user, user)` succeeds while `redeem` of shares redeeming below `10e18` reverts.

## Non-candidates / checked assumptions

- No confirmed reentrancy issue in current source; guarded functions and ordering match OZ ERC4626.
- No oracle/AMM/signature/proxy issue found in `src/`.
- `collectFees` cannot currently drain principal because `totalFeesCollected` cannot become nonzero through any current source path.
- `maxDepositLimit` is per-transaction in code; do not report cumulative-limit bypass unless Agent 4 finds docs proving cumulative intent.
