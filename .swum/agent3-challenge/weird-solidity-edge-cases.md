# Weird Solidity / EVM Edge Cases Checked

## 1. Zero-share mint on nonzero deposit

**Applies:** Yes, CAND-001.

`Vaulty.deposit` requires `assets > 0` but never requires `shares > 0`. ERC20 `_mint` accepts zero-value mints. Therefore a depositor can transfer nonzero assets and receive zero shares after donation-skewed `previewDeposit` math.

## 2. Direct ERC20 transfer into ERC4626 vault

**Applies:** Yes, CAND-001.

Inherited `totalAssets()` reads `IERC20(asset()).balanceOf(address(this))`, so unsolicited transfers affect exchange-rate math. This is not an EVM bug; it is a known ERC4626 edge case that becomes reachable and material because Vaulty has no min-share slippage guard and uses a custom first-deposit branch.

## 3. Unrestricted asset mint

**Applies:** Yes, CAND-001 and local challenge economics.

`VToken.mint` has no access control. If this token is the USDC-like asset in scope, attacker donation capital is free and the donation/inflation path becomes directly profitable instead of merely griefing or multi-victim/capital-intensive.

## 4. Unrestricted burn from arbitrary address

**Applies:** Yes, CAND-002.

`VToken.burn(from, amount)` has no approval or role check. Because OpenZeppelin `_burn` mutates balances solely for the supplied `from`, any caller can destroy the vault's underlying balance if the vault has sufficient balance.

## 5. ERC20 decimal mismatch

**Applies:** Not a concrete candidate.

`VToken` uses the default 18 decimals. README says USDC, which normally has 6 decimals, but the actual in-repo asset has 18 decimals and Vaulty relies on ERC4626 cached underlying decimals. No concrete decimal exploit exists in current source without an alternate deployed token.

## 6. ERC777 / callback reentrancy

**Applies:** Not a concrete candidate.

`Vaulty` calls `safeTransferFrom` before `_mint` on deposit/mint and burns before `safeTransfer` on withdraw/redeem, matching OZ's ERC4626 callback-safety ordering. The public asset movement functions are also `nonReentrant`.

## 7. Fee-on-transfer / deflationary token accounting

**Applies:** Not promoted for current VToken.

Vaulty assumes `assets` transferred equals assets received. This would break for fee-on-transfer tokens because shares are minted for requested `assets`, not actual received. The in-repo `VToken` is standard OZ ERC20 with no transfer fee, and Agent 2 identified the intended local asset as `VToken`, so this remains a future compatibility note rather than a candidate.

## 8. Revert after burn before transfer

**Applies:** Not a candidate.

`withdraw`/`redeem` burn before transfer, but if `safeTransfer` reverts, the entire transaction reverts and the burn is reverted too. No partial state loss under normal EVM atomicity.

## 9. `collectFees` zero-before-transfer ordering

**Applies:** Not a candidate.

`collectFees` sets `totalFeesCollected = 0` before transfer, but a transfer revert reverts the state reset. More importantly, no current path increments `totalFeesCollected`, so the function is unreachable except with future code changes.

## 10. Hardcoded script/fork addresses

**Applies:** Test/script reliability issue, not a protocol candidate.

`test/Exploit.t.sol`, `script/ExploitTx.s.sol`, and `script/SendTx.s.sol` set `Vault` and `VToken` to the same address. Local `forge test -vvv` fails the exploit test with `call to non-contract address`, so these addresses should not be used as proof of deployed behavior.
