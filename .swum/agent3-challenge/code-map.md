# SwuM Agent 3 Code Map

## Scope Read

- `README.md`: challenge objective is to steal USDC from the Vaulty contract.
- `src/Vaulty.sol`: custom ERC4626 vault and primary in-scope protocol logic.
- `src/VToken.sol`: local USDC-like ERC20 asset used by tests/deploy script.
- `test/Vault.t.sol`: local setup and first-deposit/direct-donation scenario.
- `test/Exploit.t.sol`, `script/ExploitTx.s.sol`, `script/SendTx.s.sol`: fork/script helpers, but hardcode identical vault/token addresses and are not reliable local deployment truth.
- OpenZeppelin dependency: `lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol` v5.4.0 conversion math and default `totalAssets()`.

## Contracts and Inheritance

### `Vaulty` (`src/Vaulty.sol`)

- Inherits `ERC4626`, `Ownable`, `ReentrancyGuard`.
- Constructor lines 38-47 sets:
  - underlying asset through `ERC4626(asset_)`;
  - share token name/symbol through `ERC20(name_, symbol_)`;
  - owner through `Ownable(msg.sender)`;
  - `feeRecipient` and `maxDepositLimit`.
- Does not override `totalAssets()`, `_convertToShares()`, `_convertToAssets()`, `maxDeposit()`, `maxMint()`, `maxWithdraw()`, or `maxRedeem()`.

### `VToken` (`src/VToken.sol`)

- Inherits OpenZeppelin `ERC20`.
- Constructor lines 7-13 mints `initialSupply` to deployer.
- `mint(address,uint256)` lines 15-18 is unrestricted.
- `burn(address,uint256)` lines 20-23 is unrestricted and can burn from any address with sufficient balance.

## Vault Entry Points

| Function | Lines | Guard | State reads | State writes / asset movement | Challenge notes |
| --- | ---: | --- | --- | --- | --- |
| `deposit(uint256,address)` | 50-76 | `nonReentrant`; `assets > 0`; `assets <= maxDepositLimit` | `totalSupply()`, `previewDeposit()`, `asset()` | external `safeTransferFrom`, `_mint(receiver, shares)` | First-deposit branch bypasses inherited ERC4626 virtual offset math. No `depositsEnabled`, deposit fee, or min shares check. |
| `mint(uint256,address)` | 79-104 | `nonReentrant`; `shares > 0`; `assets <= maxDepositLimit` | `totalSupply()`, `previewMint()`, `asset()` | external `safeTransferFrom`, `_mint(receiver, shares)` | Uses desired shares, so it cannot mint zero shares, but still ignores `depositsEnabled` and fees. |
| `withdraw(uint256,address,address)` | 107-126 | `nonReentrant`; `assets > 0`; allowance if caller != owner | `previewWithdraw()` | `_spendAllowance`, `_burn(owner, shares)`, external `safeTransfer` | No `withdrawalsEnabled`, no `minWithdrawAmount`, no withdraw fee. |
| `redeem(uint256,address,address)` | 129-150 | `nonReentrant`; `shares > 0`; allowance if caller != owner; `assets >= minWithdrawAmount` | `previewRedeem()` | `_spendAllowance`, `_burn(owner, shares)`, external `safeTransfer` | Checks minimum that sibling `withdraw` does not. No `withdrawalsEnabled`, no withdraw fee. |

## Privileged Paths

| Function | Lines | Role | Effect | Challenge notes |
| --- | ---: | --- | --- | --- |
| `setDepositFee` | 154-158 | owner | writes `depositFee` | Fee is never applied in deposit/mint. |
| `setWithdrawFee` | 161-165 | owner | writes `withdrawFee` | Fee is never applied in withdraw/redeem. |
| `setMaxDepositLimit` | 168-171 | owner | writes `maxDepositLimit` | Enforced as per-transaction assets, not aggregate assets. |
| `setMinWithdrawAmount` | 174-177 | owner | writes `minWithdrawAmount` | Enforced only by `redeem`, bypassed by `withdraw`. |
| `setDepositsEnabled` | 181-184 | owner | writes `depositsEnabled` | Never read by deposit/mint. |
| `setWithdrawalsEnabled` | 187-190 | owner | writes `withdrawalsEnabled` | Never read by withdraw/redeem. |
| `setFeeRecipient` | 193-197 | owner | writes `feeRecipient` | Rejects zero address. |
| `collectFees` | 200-206 | owner | sets `totalFeesCollected = 0`, transfers assets to `feeRecipient` | `totalFeesCollected` is never incremented by operational flows, so this path is unreachable unless future code mutates the variable. |

## State Variables

- `depositFee` line 15: configured, exposed by getter, not coupled to deposit/mint transfer amounts.
- `withdrawFee` line 16: configured, exposed by getter, not coupled to withdraw/redeem transfer amounts.
- `maxDepositLimit` line 17: enforced in both deposit and mint as max assets for the current call.
- `minWithdrawAmount` line 18: enforced in redeem only.
- `depositsEnabled` line 19: configured and exposed, never enforced.
- `withdrawalsEnabled` line 20: configured and exposed, never enforced.
- `feeRecipient` line 22: used only by `collectFees`.
- `totalFeesCollected` line 23: read by `collectFees` and getter; only write is reset-to-zero in `collectFees`.
- Vault share balances and `totalSupply()` are inherited ERC20 state from `ERC4626`/`ERC20`.
- Vault assets are not internally tracked; inherited `totalAssets()` returns `IERC20(asset()).balanceOf(address(this))` at OZ ERC4626 lines 116-118.

## Asset Flows

1. User deposit path: user `approve` -> `Vaulty.deposit` or `Vaulty.mint` -> `asset.safeTransferFrom(user, vault, assets)` -> Vaulty mints shares to receiver.
2. User exit path: `Vaulty.withdraw` or `Vaulty.redeem` -> burn shares -> `asset.safeTransfer(vault, receiver, assets)`.
3. Direct donation path: any holder calls `VToken.transfer(address(vaulty), amount)` or any ERC20 transfer into the vault. This increases inherited `totalAssets()` without minting shares.
4. Local free-mint path: any caller calls `VToken.mint(attacker, amount)`, then can approve/deposit/donate those tokens.
5. Local arbitrary-burn path: any caller calls `VToken.burn(address(vaulty), amount)` and decreases vault underlying balance without burning shares.

## External Calls and Ordering

- `deposit` and `mint`: compute shares/assets before `safeTransferFrom`, then mint after the transfer. This follows OZ ordering for ERC777-style safety, but the pre-transfer preview reads a manipulable raw vault balance.
- `withdraw` and `redeem`: burn before `safeTransfer`, consistent with OZ `_withdraw` ordering for reentrancy safety.
- `collectFees`: zeros `totalFeesCollected` before transfer. If `totalFeesCollected` were ever nonzero, the transfer revert would revert the zeroing too.
- No oracle reads, AMM reads, bridges, signatures, delegatecalls, upgrade hooks, or emergency withdrawal code were found in `src/`.

## Hooks, Upgrades, Emergency Paths

- No custom ERC20 transfer hooks in `Vaulty`.
- No proxy/upgradeability code.
- No `pause` modifier or emergency withdrawal despite `depositsEnabled`/`withdrawalsEnabled` flags.
- `ReentrancyGuard` is applied to the four user asset movement functions, not to owner setters or `collectFees`.

## Tests and Reachability Evidence

- `test/Vault.t.sol` lines 24-50 performs: Bob deposits 1 wei, Bob transfers `100e18` assets directly to the vault, Alice deposits `100e18`, then both withdraw 1 asset. This confirms the direct-donation state is intentionally reachable in local tests.
- `forge test --match-path test/Vault.t.sol -vvv` passes.
- Full `forge test -vvv` fails only because `test/Exploit.t.sol` calls hardcoded non-contract address `0x841ECE2d146eaD8724444e2BDA9594D4Ac0398Cc`, not because the local vault scenario is unreachable.
