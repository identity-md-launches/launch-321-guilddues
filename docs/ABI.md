# Contract interface

The JSON files under `docs/abi/` are ABI arrays exported by Solidity 0.8.26 through `forge inspect`. They include constructors, events, errors and view functions. All amounts are integer minor units; format GILD with 18 decimals. Timestamps are Unix seconds.

## LaunchToken

`LaunchToken()` has no constructor arguments. Standard ERC-20 calls are `name()`, `symbol()`, `decimals()`, `totalSupply()`, `balanceOf(address)`, `allowance(address,address)`, `approve(address,uint256)`, `transfer(address,uint256)` and `transferFrom(address,address,uint256)`. Mutation calls return `bool`; insufficient funds, insufficient allowance and prohibited zero addresses revert with the included ERC-20 custom errors. Approvals replace the allowance. The maximum uint256 allowance is treated as unlimited and is not decremented on spending.

ERC-20 `Transfer` and `Approval` events are included. There are no public mint, burn, admin or upgrade functions.

## GuildDues

Constructor: `GuildDues(address token_, address treasurer_)`, nonpayable. Use the previously deployed LaunchToken and the policy owner respectively. There is no post-deployment initialization.

| Call | Result or effect |
| --- | --- |
| `token()` | Immutable ERC-20 address |
| `treasurer()` | Immutable sweep destination |
| `pay(uint256 periods)` | Pulls `periods * 10000e18` from caller; extends caller only; nonpayable, no return value |
| `sweep()` | Sends entire GILD balance to treasurer; anyone may call; nonpayable, no return value |
| `accrued()` | Current GILD balance in minor units |
| `expiryOf(address member)` | Current Unix expiry, or zero if never paid |
| `isActive(address member)` | Whether chain timestamp is strictly less than member expiry |
| `memberCount()` | Permanent roster size, including lapsed members |
| `members(uint256 offset, uint256 limit)` | Array of tuples `(address member, uint256 expiry)` in first-payment order; `limit` clamped to 100; zero limit or offset at/beyond end returns `[]` |
| `DUES_PER_PERIOD()` | `10000000000000000000000` |
| `PERIOD()` | `2592000` seconds |
| `MAX_PERIODS()` | `12` |
| `MAX_ADVANCE()` | `157680000` seconds |
| `MAX_PAGE_SIZE()` | `100` |

Events:

```solidity
event Paid(address indexed member, uint256 periods, uint256 newExpiry);
event Swept(uint256 amount);
```

`Paid` is emitted only after the token transfer succeeds. A zero-balance sweep emits `Swept(0)`. Events aid transaction feedback, but roster and accrued balance are available directly from views. Donations emit only the token's `Transfer`, so a sum of `Paid` events alone does not measure all inflows.

App errors: `InvalidToken()`, `InvalidTreasurer()`, `InvalidPeriods()`, `ExpiryTooFar()`. `ReentrancyGuardReentrantCall()` rejects callbacks into pay or sweep. SafeERC20/Address errors and token revert data can bubble up; decode ERC-20 errors with the LaunchToken ABI as well. Solidity arithmetic panics also revert the whole transaction. The horizon check happens before the token pull, while transfer failures atomically undo tentative roster and expiry updates.

For payment, read `token()` from the app, request `approve(appAddress, periods * 10000e18)` on that token when allowance is insufficient, wait for approval confirmation, then call `pay(periods)`. Approval and payment are distinct transactions; payment can still fail if funds, allowance or membership expiry change before execution. The contract does not accept ETH with either transaction.
