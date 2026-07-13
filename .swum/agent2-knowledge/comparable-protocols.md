# Comparable Protocols and Known Risk Patterns

## Protocol Family

Vaulty is a custom ERC4626 vault over a single ERC20 asset. The nearest comparable designs are OpenZeppelin ERC4626 vaults and CTF-style ERC4626/USDC vault challenges.

## Comparable Risk Areas

### ERC4626 First-Depositor / Donation Inflation

- Comparable pattern: a first depositor mints a tiny number of shares, donates assets directly to the vault, then future deposits mint too few or zero shares because `totalAssets()` includes the donation.
- Vaulty relevance: inherited `totalAssets()` counts raw `asset().balanceOf(address(this))`, and `test/Vault.t.sol` explicitly exercises Bob depositing `1`, directly transferring `100e18` to the vault, then Alice depositing `100e18`.
- Intended challenge likely centers on whether a user can drain the vault by manipulating exchange rate with direct transfers.

### ERC4626 Raw Balance Accounting

- Comparable pattern: vault share price depends on direct token balance rather than internally tracked managed assets.
- Vaulty relevance: no `totalAssets()` override and no internal accounting variable for managed assets. Any underlying sent directly to the vault affects preview math.

### Fee/Toggle State Not Coupled to Operations

- Comparable pattern: admin-configured controls exist but operational functions do not enforce them, creating misleading trust assumptions.
- Vaulty relevance: `depositFee`, `withdrawFee`, `depositsEnabled`, and `withdrawalsEnabled` are settable/readable but not used in deposit/withdraw/mint/redeem.

### Unrestricted Test Token Mint/Burn

- Comparable pattern: challenge tokens expose unrestricted minting for local testing; production tokens such as USDC would not.
- Vaulty relevance: `VToken.mint` and `VToken.burn` are unrestricted. If VToken is in scope on a live deployment, asset supply itself is attacker-controlled. If the intended asset is real USDC, this is only a test harness artifact.

## External Reports

- No external Vaulty-specific audit reports or exploit writeups were found in the repo or Agent 1 context.
- Agent 3 should use general ERC4626 donation/inflation knowledge as comparative context, but must ground any finding in this repo's code and tests.
