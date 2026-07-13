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
