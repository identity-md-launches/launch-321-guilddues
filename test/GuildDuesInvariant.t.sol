// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {LaunchToken} from "../src/LaunchToken.sol";
import {GuildDues} from "../src/GuildDues.sol";

/// @dev Stateful model with a fixed actor set and bounded valid actions. No outside donations except donate().
contract DuesHandler is Test {
    LaunchToken public immutable token;
    GuildDues public immutable dues;
    address[4] public actors = [address(0x101), address(0x102), address(0x103), address(0x104)];
    mapping(address => uint256) public modelExpiry;
    address[] public modelRoster;
    uint256 public totalPaid;
    uint256 public totalDonated;
    uint256 public totalSwept;

    constructor(LaunchToken token_, GuildDues dues_) {
        token = token_;
        dues = dues_;
        for (uint256 i; i < actors.length; ++i) {
            vm.prank(actors[i]);
            token.approve(address(dues), type(uint256).max);
        }
    }

    function pay(uint256 actorSeed, uint256 periodSeed) external {
        address actor = actors[actorSeed % actors.length];
        uint256 periods = bound(periodSeed, 1, 12);
        uint256 now_ = vm.getBlockTimestamp();
        uint256 start = modelExpiry[actor] > now_ ? modelExpiry[actor] : now_;
        uint256 expiry = start + periods * 30 days;
        uint256 amount = periods * 10_000e18;
        if (expiry - now_ > 1825 days || token.balanceOf(actor) < amount) return;
        if (modelExpiry[actor] == 0) modelRoster.push(actor);
        modelExpiry[actor] = expiry;
        totalPaid += amount;
        vm.prank(actor);
        dues.pay(periods);
    }

    function elapse(uint256 secondsSeed) external {
        vm.warp(vm.getBlockTimestamp() + bound(secondsSeed, 0, 400 days));
    }

    function sweep(uint256 callerSeed) external {
        totalSwept += token.balanceOf(address(dues));
        vm.prank(actors[callerSeed % actors.length]);
        dues.sweep();
    }

    function donate(uint256 amountSeed) external {
        uint256 available = token.balanceOf(address(this));
        uint256 amount = bound(amountSeed, 0, available > 100_000e18 ? 100_000e18 : available);
        totalDonated += amount;
        token.transfer(address(dues), amount);
    }

    function rosterCount() external view returns (uint256) {
        return modelRoster.length;
    }
}

contract GuildDuesInvariantTest is StdInvariant, Test {
    LaunchToken private token;
    GuildDues private dues;
    DuesHandler private handler;
    address private constant TREASURER = address(0x7EA5);

    function setUp() public {
        vm.warp(1_700_000_000);
        token = new LaunchToken();
        dues = new GuildDues(address(token), TREASURER);
        handler = new DuesHandler(token, dues);
        token.transfer(address(handler), 100_000_000e18);
        for (uint256 i; i < 4; ++i) {
            token.transfer(handler.actors(i), 100_000_000e18);
        }
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = DuesHandler.pay.selector;
        selectors[1] = DuesHandler.sweep.selector;
        selectors[2] = DuesHandler.donate.selector;
        selectors[3] = DuesHandler.elapse.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_paidAndDonatedMinusSweptEqualsAccrued() public view {
        uint256 expected = handler.totalPaid() + handler.totalDonated() - handler.totalSwept();
        assertEq(dues.accrued(), expected);
        assertEq(token.balanceOf(address(dues)), expected);
        assertEq(token.balanceOf(TREASURER), handler.totalSwept());
    }

    function invariant_rosterIsUniqueOrderedAndMatchesPaidExpiries() public view {
        GuildDues.Member[] memory page = dues.members(0, 100);
        assertEq(page.length, handler.rosterCount());
        assertEq(page.length, dues.memberCount());
        for (uint256 i; i < page.length; ++i) {
            assertEq(page[i].member, handler.modelRoster(i));
            assertEq(page[i].expiry, handler.modelExpiry(page[i].member));
            assertGt(page[i].expiry, 0);
            for (uint256 j; j < i; ++j) {
                assertTrue(page[i].member != page[j].member);
            }
        }
    }

    function invariant_membershipMatchesModelAndIsNeverMoreThanFiveYearsAhead() public view {
        uint256 now_ = vm.getBlockTimestamp();
        for (uint256 i; i < 4; ++i) {
            address member = handler.actors(i);
            uint256 expiry = handler.modelExpiry(member);
            assertEq(dues.expiryOf(member), expiry);
            assertEq(dues.isActive(member), now_ < expiry);
            if (expiry > now_) assertLe(expiry - now_, 1825 days);
        }
    }

    function invariant_supplyConservedAcrossAllParticipants() public view {
        uint256 sum = token.balanceOf(address(this)) + token.balanceOf(address(handler))
            + token.balanceOf(address(dues)) + token.balanceOf(TREASURER);
        for (uint256 i; i < 4; ++i) {
            sum += token.balanceOf(handler.actors(i));
        }
        assertEq(sum, 1_000_000_000e18);
        assertEq(token.totalSupply(), sum);
    }
}
