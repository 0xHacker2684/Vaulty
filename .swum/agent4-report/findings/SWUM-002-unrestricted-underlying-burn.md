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
