# SwuM Agent 4 Final Report

Target root: `/Users/suraj/Development/Vaulty`

Agent 4 validated the five candidates from `.swum/agent3-challenge/handoff-to-agent4.md` against the Agent 1/2 context and the implementation in `src/Vaulty.sol` and `src/VToken.sol`. This report includes only candidates with a reachable path, protocol-specific unintended behavior, concrete security impact, and evidence that existing checks do not prevent the path.

## Accepted Findings

| ID | Severity | Title | Status |
| --- | --- | --- | --- |
| SWUM-001 | High | First-deposit donation can make victim deposits mint zero shares | Accepted |
| SWUM-002 | High | Anyone can burn Vaulty's underlying balance and destroy user backing | Accepted |
| SWUM-003 | Medium | Deposit and withdrawal pause toggles are not enforced | Accepted |

## Rejected Candidates

| Candidate | Decision | Reason |
| --- | --- | --- |
| CAND-004: Configured fees are never applied or accrued | Rejected as final security finding | The fee variables are dead/uncoupled and this is a real implementation inconsistency, but Agent 4 did not find a concrete security impact beyond protocol revenue/policy semantics. `collectFees()` also cannot currently drain principal because `totalFeesCollected` is never incremented through user flows. |
| CAND-005: `withdraw` bypasses `minWithdrawAmount` enforced by `redeem` | Rejected as final security finding | The sibling inconsistency is reachable, but the demonstrated impact is only minimum-withdrawal/dust-policy bypass. Agent 4 did not find a concrete fund loss, privilege escalation, accounting corruption, or denial-of-service path beyond policy semantics. |

## Validation Notes

- Required handoffs read: `.swum/agent1-provided-information/handoff-to-agent2.md`, `.swum/agent2-knowledge/handoff-to-agent3.md`, `.swum/agent3-challenge/handoff-to-agent4.md`.
- Core code reviewed: `src/Vaulty.sol`, `src/VToken.sol`, and inherited OpenZeppelin ERC4626 conversion/`totalAssets` logic.
- Local verification run: `forge test --match-path test/Vault.t.sol -vvv`.
- Result: pass (`1` test passed, `0` failed).
- Full `forge test` was not used as the primary validation signal because Agent 3 documented that `test/Exploit.t.sol` fails due to a hardcoded non-contract address unrelated to the local vault path.

---

# SWUM-001: [High] First-deposit donation can make victim deposits mint zero shares

## [High] First-deposit donation can make victim deposits mint zero shares

### Summary

`Vaulty.deposit` handles the first deposit with a custom `shares = assets` branch, then uses inherited ERC4626 `previewDeposit` for later deposits. Because inherited `totalAssets()` is the raw underlying balance of the vault, an attacker can first mint one share, transfer underlying directly to the vault, and force a later positive victim deposit to mint `0` shares while still transferring the victim's assets into the vault.

In this repository's local asset model, the donation capital is reachable at no cost because `VToken.mint(address,uint256)` is unrestricted. The attacker can therefore convert a free direct donation into a claim over victim-deposited assets.

### Impact

A victim can lose a positive deposit and receive zero vault shares. The attacker can then redeem their single share for a portion of the vault's assets, including value supplied by the victim. This is a direct user-fund loss in the local challenge scope where `VToken` represents the vault asset.

Severity is High because the path is permissionless and causes direct loss to later depositors, although the exact profit depends on the local unrestricted `VToken.mint` behavior. With a non-mintable production asset, the same zero-share victim loss remains reachable, but one-victim profitability must account for the attacker's donation cost and OpenZeppelin's virtual-share capture.

### Root Cause

`Vaulty.deposit` bypasses the inherited ERC4626 conversion logic for the first deposit and does not reject zero-share outcomes for later deposits. The vault also relies on inherited `totalAssets()`, which counts unsolicited direct token transfers as vault assets.

Relevant code:

```solidity
if (totalSupply() == 0){
    shares = assets;
}else {
     shares = previewDeposit(assets);
}

SafeERC20.safeTransferFrom(IERC20(asset()), msg.sender, address(this), assets);
_mint(receiver, shares);
```

Inherited ERC4626 conversion:

```solidity
function totalAssets() public view virtual returns (uint256) {
    return IERC20(asset()).balanceOf(address(this));
}

function _convertToShares(uint256 assets, Math.Rounding rounding) internal view virtual returns (uint256) {
    return assets.mulDiv(totalSupply() + 10 ** _decimalsOffset(), totalAssets() + 1, rounding);
}
```

### Preconditions

- The vault is empty.
- The attacker can acquire or mint underlying `VToken`. In this repository, `VToken.mint` is external and unrestricted.
- A victim subsequently deposits after the attacker's first deposit and direct donation.

### Attack Path

1. Attacker calls `VToken.mint(attacker, D + 1)`.
2. Attacker approves Vaulty and calls `Vaulty.deposit(1, attacker)`.
3. Because `totalSupply() == 0`, Vaulty mints exactly `1` share to the attacker.
4. Attacker transfers `D` `VToken` directly to `address(vaulty)` without calling `deposit`.
5. Victim approves Vaulty and calls `Vaulty.deposit(A, victim)`.
6. Vaulty computes victim shares as `floor(A * (totalSupply + 1) / (totalAssets + 1))`.
7. With `totalSupply = 1` and `totalAssets = D + 1`, victim shares are `floor(2A / (D + 2))`.
8. If `D >= 2A - 1`, the victim receives `0` shares while `safeTransferFrom` still transfers `A` assets into the vault.
9. Attacker redeems or withdraws against their single share and captures value from the victim's deposit.

Concrete example using Agent 3's suggested values:

- `A = 100e18`
- `D = 201e18`
- Victim shares: `floor(2 * 100e18 / (201e18 + 2)) = 0`
- Victim transfers `100e18` assets and receives no shares.

### Proof of Concept / Reproduction Plan

The existing test path in `test/Vault.t.sol:testFirstDeposit` already performs the key sequence: Bob deposits first, Bob directly transfers tokens to the vault, then Alice deposits. To make the test assert the exploit, add checks equivalent to:

```solidity
function testZeroShareDonationAttack() public {
    uint256 victimDeposit = 100e18;
    uint256 donation = 201e18;

    vToken.mint(bob, donation + 1);

    vm.startPrank(bob);
    vToken.approve(address(vaulty), 1);
    vaulty.deposit(1, bob);
    vToken.transfer(address(vaulty), donation);
    vm.stopPrank();

    uint256 aliceBefore = vToken.balanceOf(alice);

    vm.startPrank(alice);
    vToken.approve(address(vaulty), victimDeposit);
    uint256 shares = vaulty.deposit(victimDeposit, alice);
    vm.stopPrank();

    assertEq(shares, 0);
    assertEq(vaulty.balanceOf(alice), 0);
    assertEq(vToken.balanceOf(alice), aliceBefore - victimDeposit);
}
```

Local verification performed by Agent 4: `forge test --match-path test/Vault.t.sol -vvv` passes, confirming the repository's first-deposit/direct-transfer/deposit path is executable.

### Why Existing Checks Do Not Prevent It

- `require(assets > 0)` only rejects zero-asset deposits; it does not reject zero-share deposits.
- `maxDepositLimit` limits the victim's per-call deposit amount but does not prevent prior direct donations.
- `nonReentrant` does not prevent a donation in an earlier transaction.
- OpenZeppelin's virtual assets/shares are weakened because Vaulty special-cases the first deposit instead of consistently using ERC4626 conversion and because the vault allows minting `0` shares.
- No slippage/min-share parameter lets the depositor protect themselves.

### Recommended Fix

Use a consistent ERC4626 implementation and reject zero-share deposits. Also consider internal asset accounting if direct donations should not affect share pricing.

Minimal patch:

```diff
 function deposit(uint256 assets, address receiver)
     public
     virtual
     override
     nonReentrant
     returns (uint256)
 {
     require(assets > 0, "Cannot deposit zero");
     require(assets <= maxDepositLimit, "Exceeds max deposit limit");

-    uint256 shares;
-
-    if (totalSupply() == 0){
-        shares = assets;
-    }else {
-         shares = previewDeposit(assets);
-    }
+    uint256 shares = previewDeposit(assets);
+    require(shares > 0, "Zero shares");

     SafeERC20.safeTransferFrom(IERC20(asset()), msg.sender, address(this), assets);
     _mint(receiver, shares);
```

For stronger protection, add a user-supplied `minSharesOut` deposit path or use internal accounting that excludes unsolicited token transfers from pricing.

### Affected Code

- `src/Vaulty.sol:50-76` (`deposit`)
- `src/Vaulty.sol:62-66` (first-deposit branch)
- `src/Vaulty.sol:69-71` (asset transfer followed by mint)
- `lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol:116-118` (`totalAssets` raw balance)
- `lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol:225-227` (`_convertToShares`)
- `src/VToken.sol:15-18` (unrestricted mint in local asset model)

---

# SWUM-002: [High] Anyone can burn Vaulty's underlying balance and destroy user backing

## [High] Anyone can burn Vaulty's underlying balance and destroy user backing

### Summary

`VToken.burn(address,uint256)` is external, unrestricted, and accepts an arbitrary `from` address. Any caller can burn `VToken` directly from `address(vaulty)`, reducing Vaulty's underlying balance without burning vault shares or updating any Vaulty accounting.

Because inherited ERC4626 `totalAssets()` reads the vault's current token balance, the burn immediately destroys the asset backing for outstanding shares. Depositors can be left with shares that redeem for zero or substantially fewer assets.

### Impact

Any attacker can permanently destroy vault-held underlying assets. This causes direct user loss or a withdrawal/redeem denial of service because users' shares remain outstanding while the backing assets have been burned.

Severity is High in this repository's asset model because the attack is permissionless, requires no victim approval, and can destroy all assets held by the vault. It is destructive rather than directly profitable unless combined with an external position, but it is still concrete user-fund loss.

### Root Cause

The underlying token exposes a globally callable arbitrary-address burn function:

```solidity
function burn(address from, uint256 amount) external {
    _burn(from, amount);
}
```

Vaulty trusts this token as its ERC4626 asset and does not maintain internal accounting that can prevent token-level destruction from desynchronizing shares and backing.

### Preconditions

- Vaulty holds a positive `VToken` balance from one or more deposits.
- A victim holds Vaulty shares.
- The attacker can call `VToken.burn(address(vaulty), amount)`.

### Attack Path

1. Victim approves Vaulty and calls `Vaulty.deposit(100e18, victim)`.
2. Vaulty receives `100e18` `VToken` and mints shares to the victim.
3. Attacker calls `VToken.burn(address(vaulty), 100e18)`.
4. `VToken` burns the vault's balance because `_burn` only requires that `from` has enough balance.
5. Vaulty's `totalSupply()` is unchanged, but inherited `totalAssets()` falls to `0`.
6. Victim's later `redeem` returns `0` assets, or `withdraw` cannot recover the original deposited assets because the backing has been destroyed.

### Proof of Concept / Reproduction Plan

Add a Foundry test equivalent to:

```solidity
function testAnyoneCanBurnVaultBacking() public {
    uint256 amount = 100e18;

    vm.startPrank(alice);
    vToken.approve(address(vaulty), amount);
    vaulty.deposit(amount, alice);
    vm.stopPrank();

    assertEq(vToken.balanceOf(address(vaulty)), amount);
    assertGt(vaulty.balanceOf(alice), 0);

    address attacker = makeAddr("attacker");
    vm.prank(attacker);
    vToken.burn(address(vaulty), amount);

    assertEq(vToken.balanceOf(address(vaulty)), 0);
    assertEq(vaulty.totalAssets(), 0);
    assertGt(vaulty.balanceOf(alice), 0);
    assertEq(vaulty.previewRedeem(vaulty.balanceOf(alice)), 0);
}
```

Local verification performed by Agent 4: `forge test --match-path test/Vault.t.sol -vvv` passes, confirming the local Vaulty/VToken deployment and deposit path are executable. The burn path follows directly from `VToken.burn` being unrestricted.

### Why Existing Checks Do Not Prevent It

- `Vaulty.nonReentrant` does not apply because the attacker calls the token contract directly.
- `Vaulty.withdraw` and `Vaulty.redeem` checks execute only after the asset balance has already been destroyed.
- ERC4626 `totalAssets()` is a live token balance read, so it cannot distinguish authorized withdrawals from arbitrary burns.
- `VToken._burn` only checks that `from` has enough balance; it does not require `msg.sender == from` or allowance.

### Recommended Fix

Restrict minting and burning to an authorized role or remove arbitrary-address burn functionality from the production asset. At minimum, burning from another account should require allowance or ownership.

```diff
-function burn(address from, uint256 amount) external {
+function burn(uint256 amount) external {
+    address from = msg.sender;
     _burn(from, amount);
 }
```

If privileged mint/burn is required for tests or administration, gate it with `onlyOwner`/`AccessControl` and never grant that role to arbitrary users.

### Affected Code

- `src/VToken.sol:20-23` (`burn`)
- `src/Vaulty.sol:107-150` (`withdraw`/`redeem` observe damaged backing)
- `lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol:116-118` (`totalAssets` raw balance)

---

# SWUM-003: [Medium] Deposit and withdrawal pause toggles are not enforced

## [Medium] Deposit and withdrawal pause toggles are not enforced

### Summary

Vaulty exposes owner-controlled `setDepositsEnabled` and `setWithdrawalsEnabled` functions plus public getters and events, but none of the ERC4626 asset movement functions read these flags. A user can still call `deposit`, `mint`, `withdraw`, or `redeem` after the owner disables the corresponding operation.

### Impact

The owner cannot actually pause deposits or withdrawals during an incident. If the owner disables deposits or withdrawals to stop an exploit, an attacker can continue moving assets through the supposedly disabled paths.

Severity is Medium because this is a security-control bypass rather than an independent fund-drain primitive. It is reachable, protocol-specific, and defeats an explicit emergency/policy mechanism in the contract.

### Root Cause

The pause flags are only written and exposed through getters; operational flows do not enforce them.

```solidity
function setDepositsEnabled(bool enabled) external onlyOwner {
    depositsEnabled = enabled;
    emit DepositsToggled(enabled);
}

function setWithdrawalsEnabled(bool enabled) external onlyOwner {
    withdrawalsEnabled = enabled;
    emit WithdrawalsToggled(enabled);
}
```

`deposit`, `mint`, `withdraw`, and `redeem` check amounts, limits, allowances, and balances, but they do not check `depositsEnabled` or `withdrawalsEnabled`.

### Preconditions

- Owner calls `setDepositsEnabled(false)` or `setWithdrawalsEnabled(false)`.
- A user or attacker has the required assets/shares and approvals for the operation.

### Attack Path

1. Owner calls `setDepositsEnabled(false)` to stop new vault inflows.
2. Attacker calls `deposit(assets, attacker)` or `mint(shares, attacker)` successfully because no deposit flag is checked.
3. Owner calls `setWithdrawalsEnabled(false)` to stop outflows.
4. Attacker calls `withdraw(assets, attacker, attacker)` or `redeem(shares, attacker, attacker)` successfully because no withdrawal flag is checked.

### Proof of Concept / Reproduction Plan

Add a Foundry test equivalent to:

```solidity
function testPauseTogglesNotEnforced() public {
    vaulty.setDepositsEnabled(false);

    vm.startPrank(alice);
    vToken.approve(address(vaulty), 10e18);
    vaulty.deposit(10e18, alice); // succeeds despite disabled deposits
    vm.stopPrank();

    vaulty.setWithdrawalsEnabled(false);

    vm.prank(alice);
    vaulty.withdraw(1e18, alice, alice); // succeeds despite disabled withdrawals
}
```

Local verification performed by Agent 4: `forge test --match-path test/Vault.t.sol -vvv` passes, confirming the underlying deposit/withdraw paths are executable. Code inspection confirms no operational function references the pause flags.

### Why Existing Checks Do Not Prevent It

- `onlyOwner` protects only the setter functions; it does not enforce the resulting state.
- `assets > 0`, `shares > 0`, `maxDepositLimit`, and allowance checks are unrelated to the pause state.
- The flags are private, but public getters confirm they are intended contract state rather than unused local variables.

### Recommended Fix

Enforce the flags in all corresponding asset movement functions and initialize them to the intended default.

```diff
 constructor(...) ERC4626(asset_) ERC20(name_, symbol_) Ownable(msg.sender) {
     feeRecipient = _feeRecipient;
     maxDepositLimit = _maxDepositLimit;
+    depositsEnabled = true;
+    withdrawalsEnabled = true;
 }

 function deposit(uint256 assets, address receiver) public virtual override nonReentrant returns (uint256) {
+    require(depositsEnabled, "Deposits disabled");
     require(assets > 0, "Cannot deposit zero");
     ...
 }

 function mint(uint256 shares, address receiver) public virtual override nonReentrant returns (uint256) {
+    require(depositsEnabled, "Deposits disabled");
     require(shares > 0, "Cannot mint zero shares");
     ...
 }

 function withdraw(uint256 assets, address receiver, address owner) public virtual override nonReentrant returns (uint256) {
+    require(withdrawalsEnabled, "Withdrawals disabled");
     require(assets > 0, "Cannot withdraw zero");
     ...
 }

 function redeem(uint256 shares, address receiver, address owner) public virtual override nonReentrant returns (uint256) {
+    require(withdrawalsEnabled, "Withdrawals disabled");
     require(shares > 0, "Cannot redeem zero shares");
     ...
 }
```

### Affected Code

- `src/Vaulty.sol:50-104` (`deposit`, `mint`)
- `src/Vaulty.sol:107-150` (`withdraw`, `redeem`)
- `src/Vaulty.sol:181-190` (`setDepositsEnabled`, `setWithdrawalsEnabled`)
- `src/Vaulty.sol:229-235` (`areDepositsEnabled`, `areWithdrawalsEnabled`)
