// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @dev Test fixture only; deliberately not a supported production currency.
contract AdversarialToken is ERC20 {
    enum Mode {
        Normal,
        ReturnFalse,
        Revert,
        NoReturn
    }

    Mode public mode;
    address public callbackTarget;
    bytes public callbackData;
    bool public callbackSucceeded;
    bytes public callbackResult;
    uint256 public callbackCount;

    error TransferRejected();

    constructor() ERC20("Test", "TEST") {
        _mint(msg.sender, 1_000_000e18);
    }

    function setMode(Mode mode_) external {
        mode = mode_;
    }

    function setCallback(address target, bytes memory data) external {
        callbackTarget = target;
        callbackData = data;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        _callback();
        super.transfer(to, amount);
        return _returnValue();
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        _callback();
        super.transferFrom(from, to, amount);
        return _returnValue();
    }

    function _callback() private {
        if (callbackTarget != address(0)) {
            ++callbackCount;
            (callbackSucceeded, callbackResult) = callbackTarget.call(callbackData);
        }
    }

    function _returnValue() private view returns (bool) {
        if (mode == Mode.ReturnFalse) return false;
        if (mode == Mode.Revert) revert TransferRejected();
        if (mode == Mode.NoReturn) {
            assembly ("memory-safe") {
                return(0, 0)
            }
        }
        return true;
    }
}
