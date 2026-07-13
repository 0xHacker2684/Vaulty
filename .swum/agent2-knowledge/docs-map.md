# Docs Map

## Repository Documentation

| File | Relevance | Notes |
| --- | --- | --- |
| `README.md` | Primary challenge statement | States the game is to steal USDC from the Vaulty contract. No formal spec, threat model, deployment scope, or exclusions. |
| `foundry.toml` | Build config | Standard Foundry layout: `src`, `out`, `lib`. No protocol-specific settings. |

## Protocol Source Comments

| File | Relevance | Notes |
| --- | --- | --- |
| `src/Vaulty.sol` | Main protocol contract | NatSpec title: `Vaulty`; dev note: "Custom ERC4626 vault with deposit/withdraw fees and limits." This is the clearest intended behavior statement. |
| `src/VToken.sol` | Test/challenge asset | Comments say `mint` and `burn` are "for testing". Both are external and unrestricted. |

## Tests

| File | Relevance | Notes |
| --- | --- | --- |
| `test/Vault.t.sol` | Intent/example behavior and challenge clue | Deploys `VToken` and `Vaulty`, mints to Bob/Alice, then tests a first-depositor/direct-transfer sequence: Bob deposits 1 wei, transfers 100e18 underlying directly to the vault, Alice deposits 100e18, then both withdraw. This is an important scenario for Agent 3 to challenge. |
| `test/Exploit.t.sol` | Incomplete fork exploit sketch | Defines vault/token interfaces and hardcoded Sepolia-style addresses, mints test tokens, approves, and deposits. It incorrectly sets Vault and VToken to the same address. Treat as a rough exploit scaffold, not reliable spec. |

## Scripts and Deployment Notes

| File | Relevance | Notes |
| --- | --- | --- |
| `script/Deploy.sol` | Deployment intent | Deploys `VToken("VToken", "VLT", 1_000_000e18)` and `Vaulty(underlyingAsset, "VToken", "VLT", msg.sender, 100e18)`. Owner and fee recipient are deployer. |
| `script/SendTx.s.sol` | User action script | Mints 100e18 VToken, approves 100e18, deposits 100e18. Hardcoded Vault and VToken addresses are identical. |
| `script/ExploitTx.s.sol` | Exploit/action script | Mints 100e18 VToken, approves 1e18, deposits 1e18. Hardcoded Vault and VToken addresses are identical. |

## Prior Audit / External Docs in Repo

- No Vaulty-specific prior audit, whitepaper, formal spec, deployment note, or bug bounty scope was found.
- OpenZeppelin dependency docs/audits exist under `lib/openzeppelin-contracts/`; these document the dependency, not this Vaulty protocol.

## High-Value Docs Gaps

- No stated production deployment addresses or verified contract addresses.
- No explicit intended behavior for direct asset donations to the vault.
- No explanation for why `depositsEnabled`, `withdrawalsEnabled`, `depositFee`, and `withdrawFee` are configured but unused in operational flows.
- No explicit statement whether `VToken` unrestricted mint/burn is only a local test artifact or part of the challenge surface.
