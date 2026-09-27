// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @notice Non-refundable GILD memberships for a Sepolia test toy, conferring no off-chain rights or services.
/// @dev Configure with LaunchToken and the policy's $owner as treasurer. Neither can be changed.
contract GuildDues is ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant DUES_PER_PERIOD = 10_000e18;
    uint256 public constant PERIOD = 30 days;
    uint256 public constant MAX_PERIODS = 12;
    uint256 public constant MAX_ADVANCE = 5 * 365 days;
    uint256 public constant MAX_PAGE_SIZE = 100;

    IERC20 public immutable token;
    address public immutable treasurer;

    struct Member {
        address member;
        uint256 expiry;
    }

    mapping(address member => uint256 expiry) private _expiries;
    address[] private _roster;

    error InvalidToken();
    error InvalidTreasurer();
    error InvalidPeriods();
    error ExpiryTooFar();

    event Paid(address indexed member, uint256 periods, uint256 newExpiry);
    event Swept(uint256 amount);

    /// @param token_ Deployed fixed-supply LaunchToken, with 18 decimals and no transfer fee.
    /// @param treasurer_ Policy owner: the sole, immutable recipient of all swept GILD, with no admin power.
    constructor(address token_, address treasurer_) {
        if (token_.code.length == 0) revert InvalidToken();
        if (treasurer_ == address(0) || treasurer_ == address(this)) revert InvalidTreasurer();
        token = IERC20(token_);
        treasurer = treasurer_;
    }

    /// @notice Pay for 1–12 periods for yourself, starting at your expiry or now, whichever is later.
    /// @dev Membership and roster effects are rolled back if the approved GILD transfer fails.
    function pay(uint256 periods) external nonReentrant {
        if (periods == 0 || periods > MAX_PERIODS) revert InvalidPeriods();
        uint256 previousExpiry = _expiries[msg.sender];
        uint256 start = previousExpiry > block.timestamp ? previousExpiry : block.timestamp;
        uint256 newExpiry = start + periods * PERIOD;
        if (newExpiry - block.timestamp > MAX_ADVANCE) revert ExpiryTooFar();

        _expiries[msg.sender] = newExpiry;
        if (previousExpiry == 0) _roster.push(msg.sender);

        token.safeTransferFrom(msg.sender, address(this), periods * DUES_PER_PERIOD);
        emit Paid(msg.sender, periods, newExpiry);
    }

    /// @notice Anyone can send all accrued GILD, including direct transfers, to the immutable treasurer.
    /// @dev There is no internal dues ledger to clear. The shared guard prevents pay/sweep callbacks.
    function sweep() external nonReentrant {
        uint256 amount = accrued();
        token.safeTransfer(treasurer, amount);
        emit Swept(amount);
    }

    function accrued() public view returns (uint256) {
        return token.balanceOf(address(this));
    }

    function expiryOf(address member) external view returns (uint256) {
        return _expiries[member];
    }

    function isActive(address member) external view returns (bool) {
        return block.timestamp < _expiries[member];
    }

    function memberCount() external view returns (uint256) {
        return _roster.length;
    }

    /// @notice First-payment order, including lapsed members, with current expiries; at most 100 entries.
    /// @dev Oversized limits are clamped. An out-of-range offset or zero limit returns an empty page.
    function members(uint256 offset, uint256 limit) external view returns (Member[] memory page) {
        uint256 count = _roster.length;
        if (offset >= count || limit == 0) return new Member[](0);
        if (limit > MAX_PAGE_SIZE) limit = MAX_PAGE_SIZE;
        uint256 available = count - offset;
        if (limit > available) limit = available;

        page = new Member[](limit);
        for (uint256 i; i < limit; ++i) {
            address member = _roster[offset + i];
            page[i] = Member(member, _expiries[member]);
        }
    }
}
