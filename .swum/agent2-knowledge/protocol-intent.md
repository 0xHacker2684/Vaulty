# Protocol Intent: Vaulty

## Source Basis

- Agent 1 supplied no external user context, reports, scope, or assumptions.
- Intent is derived from `README.md`, `src/Vaulty.sol`, `src/VToken.sol`, `test/Vault.t.sol`, `test/Exploit.t.sol`, `script/Deploy.sol`, `script/SendTx.s.sol`, `script/ExploitTx.s.sol`, and `foundry.toml`.

## Intended Purpose

Vaulty is a challenge-style ERC4626 tokenized vault. The README states: "The game is that, we need to steal usdc from vaulty contract." In code, the deployed asset is `VToken`, but downstream analysis should treat it as the USDC-like asset the challenge asks attackers to drain.

The intended normal model is:

1. Users approve the vault to spend the underlying ERC20 asset.
2. Users deposit assets or mint shares.
3. The vault mints ERC20 vault shares representing a claim on the vault's underlying asset balance.
4. Users withdraw assets or redeem shares.
5. The owner can configure limits, fees, toggles, recipient, and collect accumulated fees.

## Core Assets and Accounting Units

- Underlying asset: `IERC20 asset()` from ERC4626; locally `VToken` in scripts/tests, intended as USDC-like challenge asset.
- Vault shares: `Vaulty` ERC20 shares, using the same name/symbol passed to the constructor.
- Asset accounting: inherited ERC4626 `totalAssets()` is not overridden, so it uses the underlying token balance held by the vault.
- Share supply: `totalSupply()` of Vaulty shares.
- Exchange rate: inherited ERC4626 preview/conversion math after first deposit; first deposit/mint uses a custom 1 asset = 1 share branch when `totalSupply() == 0`.
- Fee state: `depositFee`, `withdrawFee`, `totalFeesCollected`, `feeRecipient`; these are configured/readable but not applied in the current deposit/withdraw/mint/redeem flows.
- Limits/toggles: `maxDepositLimit`, `minWithdrawAmount`, `depositsEnabled`, `withdrawalsEnabled`; deposit/mint enforce `maxDepositLimit`, redeem enforces `minWithdrawAmount`, but the enable toggles are not checked by operational paths.

## Value Flow

- Entry: `deposit(assets, receiver)` and `mint(shares, receiver)` transfer underlying from `msg.sender` to `Vaulty` with `SafeERC20.safeTransferFrom` and mint shares to `receiver`.
- Accumulation: underlying remains in the vault contract. Direct transfers/donations to the vault also increase inherited ERC4626 `totalAssets()` because it is based on raw token balance.
- Exit: `withdraw(assets, receiver, owner)` burns enough shares from `owner` and transfers exact `assets` to `receiver`; `redeem(shares, receiver, owner)` burns exact shares and transfers `previewRedeem(shares)` assets.
- Privileged fee exit: `collectFees()` transfers `totalFeesCollected` assets to `feeRecipient`, but no current operational path increments `totalFeesCollected`.

## Trust Boundaries

- Users trust ERC4626 share accounting to preserve proportional ownership of vault assets.
- Users trust the owner not to set punitive or blocking parameters (`maxDepositLimit`, `minWithdrawAmount`, fee variables, `feeRecipient`) if these are made effective.
- Users do not need to trust another user, but the vault currently counts unsolicited token transfers as vault assets through inherited `totalAssets()`.
- The local `VToken` is not permissioned: anyone can call `mint` or `burn`. This fits testing/challenge use, but it is not a production USDC trust model.
- Scripts hardcode the same address for Vault and VToken in exploit/send scripts; Agent 3 should not assume those scripts are valid deployment truth without checking chain state.

## Privileged Roles

- `owner`: constructor `Ownable(msg.sender)`; can call all setter functions and `collectFees()`.
- `feeRecipient`: receives collected fees if `collectFees()` has nonzero `totalFeesCollected`; set in constructor and mutable by owner.
- `VToken` has no owner/minter role despite comments saying "for testing"; `mint` and `burn` are externally callable by anyone.

## External Dependencies

- OpenZeppelin `ERC4626`, `ERC20`, `Ownable`, `ReentrancyGuard`, `SafeERC20` via imported ERC4626 utilities.
- Foundry/forge-std for tests and scripts.
- Environment variables in scripts: `PRIVATE_KEY`, `SEPOLIA_RPC_URL`, `ETHERSCAN_API_KEY`.
- No oracle, AMM, bridge, lending market, governance module, or permit/signature dependency appears in repo source.

## Critical Invariants

- Every share should represent a proportional claim on the underlying assets held by the vault.
- A user should not be able to extract more underlying than their shares entitle them to under the intended exchange rate.
- Deposits/mints should not dilute existing users except according to ERC4626 rounding rules.
- Withdraw/redeem should burn the shares needed for assets paid out before or atomically with asset transfer.
- `maxDepositLimit` should bound asset entry through deposit/mint.
- If deposits/withdrawals are intended to be toggleable, the toggles should actually gate deposit/mint and withdraw/redeem.
- If fees are intended, fee variables and `totalFeesCollected` should be reflected in deposit/withdraw/mint/redeem accounting.
- Direct asset transfers to the vault should not allow an attacker to manipulate other users' share issuance or redemption value unless that behavior is explicitly accepted.
