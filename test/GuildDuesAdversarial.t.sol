// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {GuildDues} from "../src/GuildDues.sol";
import {AdversarialToken} from "./helpers/AdversarialToken.sol";

contract GuildDuesAdversarialTest is Test {
    AdversarialToken private token;
    GuildDues private dues;
    address private constant TREASURER = address(0x7EA5);
    uint256 private constant RATE = 10_000e18;

    function setUp() public {
        vm.warp(1_700_000_000);
        token = new AdversarialToken();
        dues = new GuildDues(address(token), TREASURER);
        token.approve(address(dues), type(uint256).max);
    }

    function test_falseReturnPaymentRevertsAllEffectsAndCanRetry() public {
        token.setMode(AdversarialToken.Mode.ReturnFalse);
        vm.expectRevert(abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(token)));
        dues.pay(1);
        _assertNoPayment();
        token.setMode(AdversarialToken.Mode.Normal);
        dues.pay(1);
        assertEq(dues.memberCount(), 1);
        assertEq(dues.accrued(), RATE);
    }

    function test_revertingPaymentRevertsAllEffects() public {
        token.setMode(AdversarialToken.Mode.Revert);
        vm.expectRevert(AdversarialToken.TransferRejected.selector);
        dues.pay(1);
        _assertNoPayment();
    }

    function test_failedSweepPreservesFundsAndMembershipThenRetries() public {
        dues.pay(2);
        uint256 expiry = dues.expiryOf(address(this));
        token.setMode(AdversarialToken.Mode.ReturnFalse);
        vm.expectRevert(abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(token)));
        dues.sweep();
        _assertUnchangedAfterFailedSweep(expiry);

        token.setMode(AdversarialToken.Mode.Revert);
        vm.expectRevert(AdversarialToken.TransferRejected.selector);
        dues.sweep();
        _assertUnchangedAfterFailedSweep(expiry);

        token.setMode(AdversarialToken.Mode.Normal);
        dues.sweep();
        assertEq(dues.accrued(), 0);
        assertEq(token.balanceOf(TREASURER), 2 * RATE);
    }

    function test_safeERC20AcceptsNoReturnTransfers() public {
        token.setMode(AdversarialToken.Mode.NoReturn);
        dues.pay(1);
        assertEq(dues.accrued(), RATE);
        assertEq(dues.expiryOf(address(this)), block.timestamp + 30 days);
        dues.sweep();
        assertEq(dues.accrued(), 0);
        assertEq(token.balanceOf(TREASURER), RATE);
    }

    function test_payCannotReenterPay() public {
        _checkReentry(true, true);
    }

    function test_payCannotReenterSweep() public {
        _checkReentry(true, false);
    }

    function test_sweepCannotReenterPay() public {
        _checkReentry(false, true);
    }

    function test_sweepCannotReenterSweep() public {
        _checkReentry(false, false);
    }

    function _checkReentry(bool outerPay, bool innerPay) private {
        if (!outerPay) dues.pay(1);
        bytes memory payload = innerPay ? abi.encodeCall(dues.pay, (1)) : abi.encodeCall(dues.sweep, ());
        token.setCallback(address(dues), payload);
        if (outerPay) dues.pay(1);
        else dues.sweep();

        assertEq(token.callbackCount(), 1);
        assertFalse(token.callbackSucceeded());
        assertEq(token.callbackResult(), abi.encodeWithSelector(ReentrancyGuard.ReentrancyGuardReentrantCall.selector));
        assertEq(dues.memberCount(), 1);
        assertEq(dues.expiryOf(address(this)), block.timestamp + 30 days);
        assertEq(dues.expiryOf(address(token)), 0);
        assertEq(dues.accrued(), outerPay ? RATE : 0);
        assertEq(token.balanceOf(TREASURER), outerPay ? 0 : RATE);
    }

    function _assertNoPayment() private view {
        assertEq(dues.expiryOf(address(this)), 0);
        assertEq(dues.memberCount(), 0);
        assertEq(dues.accrued(), 0);
        assertEq(token.balanceOf(address(this)), 1_000_000e18);
    }

    function _assertUnchangedAfterFailedSweep(uint256 expiry) private view {
        assertEq(dues.accrued(), 2 * RATE);
        assertEq(token.balanceOf(TREASURER), 0);
        assertEq(dues.expiryOf(address(this)), expiry);
        assertEq(dues.memberCount(), 1);
    }
}
