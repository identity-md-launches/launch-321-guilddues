# Guild dues — Sepolia test toy

Guild (GILD) and GuildDues are a Sepolia test toy. **Membership carries no off-chain rights or services.** Dues are non-refundable; leave by letting membership lapse.

This contribution delivers contracts, Foundry tests, vendored dependencies, ABI exports and integration notes. The separate manifest assignment writes `launch.json`. An independent contributor reviews the accepted contracts and manifest before services publish source, attest, admit and deploy through ProjectFactory. Services then start the website work against the live addresses. This repository does not broadcast transactions.

## Build and test

```sh
forge build
forge test
forge fmt --check
sh scripts/export-abis.sh
```

`foundry.toml` pins Solidity **0.8.26**, the Paris EVM target, optimization at 200 runs and `bytecode_hash = "none"`. No FFI, filesystem cheatcode permissions, remote RPC or environment variables are needed by the tests. Dependencies are ordinary files in `lib/`; see [versions, sources and licenses](docs/DEPENDENCIES.md). With Foundry and the pinned compiler installed, builds and tests need no network.

## Contracts and deployment parameters

| Artifact | Constructor arguments | Configuration |
| --- | --- | --- |
| `src/LaunchToken.sol:LaunchToken` | None | Guild / GILD; 18 decimals; exactly `1000000000000000000000000000` minor units (1 billion GILD), minted once to `msg.sender` |
| `src/GuildDues.sol:GuildDues` | `(address token_, address treasurer_)` | `[$token, $owner]` in that order; both immutable and publicly readable |

Deploy only on **Sepolia, chain ID 11155111**, as an `evm_project` with LaunchToken and exactly one application contract, GuildDues. The token must be deployed before the app. The factory is the token's constructor caller and receives the entire supply. GuildDues takes the policy owner explicitly as its treasurer; the factory receives no app authority. Constructors are nonpayable and complete configuration without initialization calls or any GILD balance in the app.

The GuildDues constructor rejects a token address with no deployed code and a zero or self treasurer. This is not token identity verification: the manifest and independent review must confirm that `$token` resolves to this LaunchToken and `$owner` resolves to the intended policy owner. There is no owner role, mint entry point, transfer fee, blocklist, pause, upgrade, refund, rescue or configuration setter in the production contracts. The treasurer only receives swept dues and cannot change memberships or redirect funds.

The separate manifest uses `kind: "evm_project"`, token identifier `LaunchToken`, application identifier `GuildDues`, and application `constructorArgs: ["$token", "$owner"]`. Policy and signed artifact linkage belong to services. Services resolve policy values and source artifacts, validate constructor arguments and source, and perform admission and deployment; passing local tests is not an admission artifact.

## Membership and funds

- Approve GuildDues to spend GILD, then call `pay(periods)` with an integer from 1 through 12. Each period costs **10,000 GILD** (`10000e18`) and lasts **30 days** (`2592000` seconds).
- A successful payment affects only its caller: `newExpiry = max(block.timestamp, previousExpiry) + periods * 30 days`. Renewals stack. Lapsed members restart from now and owe no back dues. A member is active strictly before expiry, and inactive exactly at expiry.
- Payments that would put expiry more than **1,825 days** (`5 * 365 days`) ahead of the current block timestamp revert before charging. Exactly that horizon is allowed. All arithmetic is checked; “five years” means a fixed seconds interval, not calendar years.
- First successful payment appends the member once to the permanent roster. Later payments update expiry without appending; lapse never removes a member. Failed transfers roll back both membership and roster changes.
- Dues stay in the app until anyone calls `sweep()`. It transfers the entire GILD balance to the immutable treasurer. Caller identity cannot choose a recipient. Both payment and sweep share a reentrancy guard; payment applies membership effects before its SafeERC20 transfer. Sweep has no separate liability ledger to clear.
- `accrued()` is the actual GILD balance, including direct GILD transfers. With no donations, total dues paid minus total swept equals that balance. With donations, add them to total inflows. A failed sweep reverts without losing funds and can be retried. Empty sweeps succeed and emit `Swept(0)`.

GILD is the only supported working currency: this LaunchToken has exact transfers, 18 decimals, and no fees, rebase or hooks. SafeERC20 detects reverts and false return values; it does not make arbitrary malicious or fee-on-transfer tokens suitable for this app. The token mock tests exercise failure handling and callbacks, not production token alternatives.

Membership uses the chain's timestamp; no oracle, randomness or keeper is involved. All app functions are nonpayable and there is no receive/fallback, so ordinary ETH transfers revert. EVM-forced ETH and unrelated ERC-20 transfers are outside the supported flows and have no rescue path. Users should send only GILD to the app and retain Sepolia ETH for gas.

## ABI and website handoff

[ABI usage](docs/ABI.md) describes the callable interface; generated arrays are [LaunchToken.json](docs/abi/LaunchToken.json) and [GuildDues.json](docs/abi/GuildDues.json). Regenerate them after changing source using the command above.

After services provide the reviewed live deployment, the one-page site `lab-guild-dues` must:

- Enforce Sepolia in the wallet flow, read the GILD address from `GuildDues.token()`, and display the wallet's GILD balance and allowance. Explain that GILD comes from swapping Sepolia ETH in the factory-seeded ETH/GILD launch pool; there is no in-page swap.
- Provide a 1–12 periods selector, show the GILD cost, require approval before payment, then refresh balance, allowance, expiry and accrued dues after confirmed receipts. Members need enough GILD; approval alone does not fund payment.
- Read the paginated roster directly from contract views, showing active/lapsed status and expiry dates, plus accrued GILD and a permissionless sweep button. No backend or indexer is needed. Use a consistent block for page reads where possible; expiry values can change between reads.
- State prominently that this is a Sepolia test toy with no off-chain rights or services and non-refundable dues. Produce a small static export with `dist/index.html` for the approved GitHub/IPFS publication.

The treasurer is responsible for its receiving wallet. Users initiate renewals and any wallet can initiate sweeps; no operator can undo a mistaken payment or change the immutable addresses. Actual deployment addresses and service policy values remain service inputs, not hard-coded privileged wallets here.

## Validation and review boundary

Tests cover token supply and exact transfers, allowance failures, constructor configuration, forbidden runtime opcodes, period bounds, stacked renewals, lapse boundaries, restart after lapse, exact five-year limits, arithmetic overflow, pagination including extreme integers, roster uniqueness, caller-independent treasury routing, donations, events, ETH rejection and the lack of common privileged selectors. Adversarial fixtures exercise false-return/reverting transfers, retriable sweep failures and all four pay/sweep reentry combinations. Stateful invariant tests interleave payments, time changes, donations and sweeps against a membership model and check conservation of GILD.

These are implementer tests, not an independent security audit. The separately assigned reviewer must inspect the final source and manifest for redirectable dues, free or overflowing extensions, duplicate roster entries and constructor arguments granting unintended authority. No external review or live deployment is claimed by this contribution.
