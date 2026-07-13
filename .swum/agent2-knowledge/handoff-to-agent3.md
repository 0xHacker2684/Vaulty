# SwuM Agent 2 Handoff to Agent 3

## Intended Protocol Behavior

Vaulty is intended to be a custom ERC4626 vault with deposit/withdraw fees and limits over a USDC-like ERC20 asset. In this repo the asset is `VToken`; README frames the objective as stealing USDC from Vaulty, so Agent 3 should challenge the vault as a single-asset tokenized vault whose underlying represents the value to drain.

Normal intended flow:

1. User approves underlying to Vaulty.
2. User calls `deposit(assets, receiver)` or `mint(shares, receiver)`.
3. Vault receives underlying and mints shares.
4. User later calls `withdraw(assets, receiver, owner)` or `redeem(shares, receiver, owner)`.
5. Vault burns shares and transfers underlying assets out.

## Unintended / Suspicious Behavior to Challenge

- Direct token transfers to the vault are counted in inherited ERC4626 `totalAssets()`; tests explicitly exercise first deposit plus direct donation before another deposit.
- `depositFee` and `withdrawFee` are never applied to operational flows, and `totalFeesCollected` is never incremented in those flows.
- `depositsEnabled` and `withdrawalsEnabled` are never checked by deposit/mint/withdraw/redeem.
- `withdraw` does not enforce `minWithdrawAmount`; `redeem` does.
- `VToken.mint` and `VToken.burn` are unrestricted despite comments saying they are for testing.
- `test/Exploit.t.sol` and scripts hardcode the same address for vault and token, so do not treat script addresses as reliable without validation.

## Core Assets and Accounting Units

- Underlying asset: `Vaulty.asset()`, locally `VToken`, challenge-described as USDC.
- Vault share: `Vaulty` ERC20 share token.
- `totalAssets()`: inherited ERC4626, based on the underlying asset balance held by Vaulty.
- `totalSupply()`: outstanding Vaulty shares.
- First deposit/mint special case: when `totalSupply() == 0`, `deposit` mints `assets` shares and `mint` requires `shares` assets.
- Subsequent conversion: uses inherited `previewDeposit`, `previewMint`, `previewWithdraw`, `previewRedeem`.
- Admin accounting variables: `depositFee`, `withdrawFee`, `maxDepositLimit`, `minWithdrawAmount`, `depositsEnabled`, `withdrawalsEnabled`, `feeRecipient`, `totalFeesCollected`.

## Trust Boundaries

- Users depend on share-price math not being manipulable by other users.
- Users depend on vault shares being a faithful claim on underlying assets.
- Owner controls settings and fee recipient; owner is trusted not to grief with configuration.
- The underlying token is trusted in a production USDC-like model, but local `VToken` is attacker-mintable/burnable.
- No oracle/AMM/bridge/lending/governance trust boundary appears in protocol source.

## Privileged Roles

- Vault owner: deployer via `Ownable(msg.sender)`. Can call `setDepositFee`, `setWithdrawFee`, `setMaxDepositLimit`, `setMinWithdrawAmount`, `setDepositsEnabled`, `setWithdrawalsEnabled`, `setFeeRecipient`, and `collectFees`.
- Fee recipient: constructor `_feeRecipient`, mutable by owner; receives `collectFees()` transfers if `totalFeesCollected > 0`.
- VToken has no privileged minter/burner; every external caller can mint or burn.

## External Dependencies

- OpenZeppelin ERC4626/ERC20/Ownable/ReentrancyGuard/SafeERC20.
- Foundry/forge-std tests and scripts.
- Deployment/script environment variables: `PRIVATE_KEY`, `SEPOLIA_RPC_URL`, `ETHERSCAN_API_KEY`.
- No Chainlink/Pyth oracle, AMM spot pricing, bridge messaging, external lending market, or signature permit flow found in repo protocol code.

## Critical Invariants

1. A user cannot withdraw/redeem more underlying than their shares should represent.
2. Share issuance must not let a depositor acquire claims on assets they did not contribute, except normal ERC4626 rounding dust.
3. Direct underlying transfers should not allow one user to dilute or confiscate another user's deposits unless explicitly intended.
4. Total vault shares and underlying assets must remain coupled through a sane exchange rate before and after the first deposit.
5. Deposit/mint limit checks must bound all asset inflow paths they are intended to cover.
6. Withdraw/redeem minimum and enable toggles must be consistently enforced if they are part of intended access control.
7. Fee variables and `totalFeesCollected` must be coupled to transfer amounts if fees are intended behavior.
8. Owner-only functions should not allow non-owner asset extraction except through explicitly accrued fees.
9. Reentrancy protection should cover all state-changing external asset movement paths.
10. Local `VToken` unrestricted mint/burn should not be confused with a production USDC trust model unless challenge scope includes it.

## Assumptions Agent 3 Must Challenge Line by Line

- Does inherited ERC4626 conversion math, combined with Vaulty's custom first-deposit branch, preserve fair share issuance after unsolicited donations?
- Does `test/Vault.t.sol` encode the intended exploit path or a regression test that currently lacks assertions?
- Are `deposit` and `mint` equivalent and safe siblings, or can one path bypass checks/accounting expected in the other?
- Are `withdraw` and `redeem` equivalent and safe siblings, or does `minWithdrawAmount` only protecting `redeem` create an inconsistent path?
- Are fees/toggles dead state, incomplete implementation, or intentionally unused challenge bait?
- Can `collectFees()` ever transfer real assets under current code, and can owner-controlled fee state desynchronize with vault liabilities?
- If VToken is in scope, does unrestricted `mint` or `burn` trivially break the asset model? If not in scope, ignore it as test-only.
- Do scripts' hardcoded identical Vault/VToken addresses indicate deployment mistakes, or are they incomplete scaffolding irrelevant to the core vulnerability?
