// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {LaunchToken} from "../src/LaunchToken.sol";
import {GuildDues} from "../src/GuildDues.sol";

contract GuildDuesTest is Test {
    LaunchToken private token;
    GuildDues private dues;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant TREASURER = address(0x7EA5);
    uint256 private constant RATE = 10_000e18;
    uint256 private constant PERIOD = 30 days;

    event Paid(address indexed member, uint256 periods, uint256 newExpiry);
    event Swept(uint256 amount);

    function setUp() public {
        vm.warp(1_700_000_000);
        token = new LaunchToken();
        dues = new GuildDues(address(token), TREASURER);
        _fundAndApprove(ALICE);
        _fundAndApprove(BOB);
    }

    function test_constructorAndUnregisteredViews() public view {
        assertEq(address(dues.token()), address(token));
        assertEq(dues.treasurer(), TREASURER);
        assertEq(dues.accrued(), 0);
        assertEq(dues.memberCount(), 0);
        assertEq(dues.expiryOf(ALICE), 0);
        assertFalse(dues.isActive(ALICE));
        assertEq(dues.members(0, 100).length, 0);
    }

    function test_constructorRejectsZeroAndCodelessTokenAndZeroTreasurer() public {
        vm.expectRevert(GuildDues.InvalidToken.selector);
        new GuildDues(address(0), TREASURER);
        vm.expectRevert(GuildDues.InvalidToken.selector);
        new GuildDues(ALICE, TREASURER);
        vm.expectRevert(GuildDues.InvalidTreasurer.selector);
        new GuildDues(address(token), address(0));
    }

    function test_payEmitsAndOnlyExtendsCaller() public {
        uint256 beforeBalance = token.balanceOf(ALICE);
        vm.expectEmit(true, false, false, true, address(dues));
        emit Paid(ALICE, 3, block.timestamp + 3 * PERIOD);
        _pay(ALICE, 3);
        assertEq(dues.expiryOf(ALICE), block.timestamp + 3 * PERIOD);
        assertEq(dues.expiryOf(BOB), 0);
        assertEq(dues.expiryOf(TREASURER), 0);
        assertTrue(dues.isActive(ALICE));
        assertEq(token.balanceOf(ALICE), beforeBalance - 3 * RATE);
        assertEq(dues.accrued(), 3 * RATE);
        assertEq(dues.memberCount(), 1);
    }

    function test_stackingRenewalsAndNoDuplicateRoster() public {
        uint256 start = vm.getBlockTimestamp();
        _pay(ALICE, 1);
        vm.warp(start + 15 days);
        _pay(ALICE, 12);
        _pay(BOB, 1);
        _pay(ALICE, 2);
        assertEq(dues.expiryOf(ALICE), start + 15 * PERIOD);
        assertEq(dues.memberCount(), 2);
        GuildDues.Member[] memory page = dues.members(0, 100);
        assertEq(page[0].member, ALICE);
        assertEq(page[0].expiry, start + 15 * PERIOD);
        assertEq(page[1].member, BOB);
    }

    function test_inactiveExactlyAtExpiryAndPayAtBoundary() public {
        _pay(ALICE, 1);
        uint256 expiry = dues.expiryOf(ALICE);
        vm.warp(expiry - 1);
        assertTrue(dues.isActive(ALICE));
        vm.warp(expiry);
        assertFalse(dues.isActive(ALICE));
        _pay(ALICE, 1);
        assertEq(dues.expiryOf(ALICE), expiry + PERIOD);
        assertTrue(dues.isActive(ALICE));
        assertEq(dues.memberCount(), 1);
    }

    function test_lapsedMemberRestartsFromNowWithoutBackDues() public {
        _pay(ALICE, 2);
        uint256 oldExpiry = dues.expiryOf(ALICE);
        vm.warp(oldExpiry + 600 days);
        assertFalse(dues.isActive(ALICE));
        assertEq(dues.members(0, 1)[0].expiry, oldExpiry);
        _pay(ALICE, 1);
        assertEq(dues.expiryOf(ALICE), block.timestamp + PERIOD);
        assertEq(dues.accrued(), 3 * RATE);
        assertEq(dues.memberCount(), 1);
    }

    function test_fiveYearCapRejectsBeforeChargingAndAllowsExactBoundary() public {
        for (uint256 i; i < 5; ++i) {
            _pay(ALICE, 12);
        }
        uint256 expiry = dues.expiryOf(ALICE);
        uint256 balance = token.balanceOf(ALICE);
        vm.expectRevert(GuildDues.ExpiryTooFar.selector);
        _pay(ALICE, 1);
        assertEq(dues.expiryOf(ALICE), expiry);
        assertEq(token.balanceOf(ALICE), balance);

        vm.warp(vm.getBlockTimestamp() + 5 days - 1);
        vm.expectRevert(GuildDues.ExpiryTooFar.selector);
        _pay(ALICE, 1);
        vm.warp(vm.getBlockTimestamp() + 1);
        _pay(ALICE, 1);
        assertEq(dues.expiryOf(ALICE) - block.timestamp, 5 * 365 days);
        assertEq(dues.accrued(), 61 * RATE);
        vm.expectRevert(GuildDues.ExpiryTooFar.selector);
        _pay(ALICE, 1);
        assertEq(dues.memberCount(), 1);
    }

    function test_zeroThirteenAndMaximumPeriodsRevert() public {
        _invalidPeriods(0);
        _invalidPeriods(13);
        _invalidPeriods(type(uint256).max);
    }

    function testFuzz_invalidPeriodsCannotCreateMembership(uint256 periods) public {
        periods = bound(periods, 13, type(uint256).max);
        _invalidPeriods(periods);
    }

    function test_missingAllowanceRollsBackExpiryAndRoster() public {
        vm.prank(ALICE);
        token.approve(address(dues), 0);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(dues), 0, RATE)
        );
        _pay(ALICE, 1);
        assertEq(dues.expiryOf(ALICE), 0);
        assertEq(dues.memberCount(), 0);
        assertEq(dues.accrued(), 0);
    }

    function test_insufficientBalanceRollsBackRenewalAndAllowance() public {
        _pay(ALICE, 1);
        uint256 expiry = dues.expiryOf(ALICE);
        vm.startPrank(ALICE);
        token.transfer(BOB, token.balanceOf(ALICE));
        token.approve(address(dues), RATE);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, RATE));
        dues.pay(1);
        vm.stopPrank();
        assertEq(dues.expiryOf(ALICE), expiry);
        assertEq(dues.memberCount(), 1);
        assertEq(token.allowance(ALICE, address(dues)), RATE);
        assertEq(dues.accrued(), RATE);
    }

    function testFuzz_paginationClampsAndDoesNotOverflow(uint256 offset, uint256 limit) public {
        _pay(ALICE, 1);
        _pay(BOB, 2);
        GuildDues.Member[] memory page = dues.members(offset, limit);
        uint256 expected = offset >= 2 ? 0 : 2 - offset;
        if (limit < expected) expected = limit;
        assertEq(page.length, expected);
        for (uint256 i; i < expected; ++i) {
            assertEq(page[i].member, offset + i == 0 ? ALICE : BOB);
            assertEq(page[i].expiry, dues.expiryOf(page[i].member));
        }
    }

    function test_paginationEdgesAndHundredMemberCap() public {
        for (uint256 i; i < 105; ++i) {
            address member = address(uint160(0x10000 + i));
            _fundAndApprove(member);
            _pay(member, 1);
        }
        assertEq(dues.members(0, 0).length, 0);
        assertEq(dues.members(105, 100).length, 0);
        assertEq(dues.members(type(uint256).max, type(uint256).max).length, 0);
        GuildDues.Member[] memory first = dues.members(0, type(uint256).max);
        assertEq(first.length, 100);
        GuildDues.Member[] memory last = dues.members(100, 100);
        assertEq(last.length, 5);
        for (uint256 i; i < first.length; ++i) {
            assertEq(first[i].member, address(uint160(0x10000 + i)));
        }
        for (uint256 i; i < last.length; ++i) {
            assertEq(last[i].member, address(uint160(0x10064 + i)));
        }
        assertEq(dues.members(104, 1)[0].expiry, block.timestamp + PERIOD);
    }

    function testFuzz_anyCallerSweepsOnlyToTreasurer(address caller) public {
        _pay(ALICE, 2);
        _pay(BOB, 3);
        uint256 callerBefore = token.balanceOf(caller);
        uint256 treasuryBefore = token.balanceOf(TREASURER);
        vm.expectEmit(false, false, false, true, address(dues));
        emit Swept(5 * RATE);
        vm.prank(caller);
        dues.sweep();
        assertEq(token.balanceOf(TREASURER), treasuryBefore + 5 * RATE);
        assertEq(dues.accrued(), 0);
        if (caller != TREASURER && caller != address(dues)) assertEq(token.balanceOf(caller), callerBefore);
        assertEq(dues.expiryOf(ALICE), block.timestamp + 2 * PERIOD);
        assertEq(dues.expiryOf(BOB), block.timestamp + 3 * PERIOD);
    }

    function test_directTransfersAndRepeatedEmptySweeps() public {
        _pay(ALICE, 1);
        token.transfer(address(dues), 123);
        assertEq(dues.accrued(), RATE + 123);
        dues.sweep();
        assertEq(token.balanceOf(TREASURER), RATE + 123);
        vm.expectEmit(false, false, false, true, address(dues));
        emit Swept(0);
        dues.sweep();
        assertEq(dues.accrued(), 0);
        assertEq(token.balanceOf(TREASURER), RATE + 123);
    }

    function testFuzz_duesPaidMinusSweptEqualsBalance(uint256 first, uint256 second, uint256 third) public {
        first = bound(first, 1, 12);
        second = bound(second, 1, 12);
        third = bound(third, 1, 12);
        _pay(ALICE, first);
        _pay(BOB, second);
        uint256 paid = (first + second) * RATE;
        assertEq(dues.accrued(), paid);
        dues.sweep();
        uint256 swept = paid;
        assertEq(dues.accrued(), paid - swept);
        _pay(ALICE, third);
        paid += third * RATE;
        assertEq(dues.accrued(), paid - swept);
        assertEq(token.balanceOf(TREASURER), swept);
    }

    function test_treasurerHasNoRedirectRefundPauseOrExpiryPowers() public {
        _pay(ALICE, 1);
        string[6] memory selectors = [
            "setTreasurer(address)",
            "sweep(address)",
            "refund(address)",
            "pause()",
            "upgradeTo(address)",
            "setExpiry(address,uint256)"
        ];
        for (uint256 i; i < selectors.length; ++i) {
            vm.prank(TREASURER);
            (bool ok,) = address(dues).call(abi.encodeWithSignature(selectors[i], BOB, type(uint256).max));
            assertFalse(ok);
        }
        assertEq(dues.treasurer(), TREASURER);
        assertEq(dues.expiryOf(ALICE), block.timestamp + PERIOD);
        assertEq(dues.accrued(), RATE);
        assertEq(token.balanceOf(TREASURER), 0);
    }

    function test_rejectsETHAndUnknownCalls() public {
        vm.deal(address(this), 4 ether);
        (bool plain,) = address(dues).call{value: 1 ether}("");
        (bool paid,) = address(dues).call{value: 1 ether}(abi.encodeCall(dues.pay, (1)));
        (bool swept,) = address(dues).call{value: 1 ether}(abi.encodeCall(dues.sweep, ()));
        (bool unknown,) = address(dues).call(hex"12345678");
        assertFalse(plain);
        assertFalse(paid);
        assertFalse(swept);
        assertFalse(unknown);
        assertEq(address(dues).balance, 0);
    }

    function test_expiryArithmeticCannotWrapIntoFreeExtension() public {
        vm.warp(type(uint256).max - PERIOD + 1);
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11));
        _pay(ALICE, 1);
        assertEq(dues.expiryOf(ALICE), 0);
        assertEq(dues.memberCount(), 0);
        assertEq(dues.accrued(), 0);
    }

    function _invalidPeriods(uint256 periods) private {
        vm.expectRevert(GuildDues.InvalidPeriods.selector);
        _pay(ALICE, periods);
        assertEq(dues.expiryOf(ALICE), 0);
        assertEq(dues.memberCount(), 0);
        assertEq(dues.accrued(), 0);
    }

    function _pay(address member, uint256 periods) private {
        vm.prank(member);
        dues.pay(periods);
    }

    function _fundAndApprove(address member) private {
        token.transfer(member, 1_000_000e18);
        vm.prank(member);
        token.approve(address(dues), type(uint256).max);
    }
}
