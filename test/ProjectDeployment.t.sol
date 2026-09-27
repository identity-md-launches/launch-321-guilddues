// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {LaunchToken} from "../src/LaunchToken.sol";
import {GuildDues} from "../src/GuildDues.sol";

/// @dev Local factory fixture; no wallet, environment, broadcast or initialization calls.
contract FactoryFixture {
    function deploy(address policyOwner) external returns (LaunchToken token, GuildDues dues) {
        token = new LaunchToken{salt: bytes32(uint256(1))}();
        dues = new GuildDues{salt: bytes32(uint256(2))}(address(token), policyOwner);
    }
}

contract ProjectDeploymentTest is Test {
    function test_factoryDeploymentPreservesSupplyAndConfiguresOnlyTreasurer() public {
        vm.chainId(11155111);
        FactoryFixture factory = new FactoryFixture();
        address owner = address(0x123456);
        (LaunchToken token, GuildDues dues) = factory.deploy(owner);
        assertEq(token.balanceOf(address(factory)), 1_000_000_000e18);
        assertEq(token.totalSupply(), 1_000_000_000e18);
        assertEq(token.balanceOf(address(dues)), 0);
        assertEq(address(dues.token()), address(token));
        assertEq(dues.treasurer(), owner);
        assertTrue(dues.treasurer() != address(factory));
        assertEq(dues.memberCount(), 0);
        assertEq(dues.accrued(), 0);
        _assertRuntime(address(token));
        _assertRuntime(address(dues));
    }

    function test_constructorRejectsETH() public {
        LaunchToken token = new LaunchToken();
        bytes memory code = abi.encodePacked(type(GuildDues).creationCode, abi.encode(address(token), address(0x1234)));
        vm.deal(address(this), 1 ether);
        address deployed;
        assembly ("memory-safe") {
            deployed := create(1, add(code, 32), mload(code))
        }
        assertEq(deployed, address(0));
    }

    function test_constructorRejectsSelfAsTreasurer() public {
        LaunchToken token = new LaunchToken();
        // Predict the next CREATE address before encoding the constructor arguments.
        address predicted = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        vm.expectRevert(GuildDues.InvalidTreasurer.selector);
        new GuildDues(address(token), predicted);
    }

    function _assertRuntime(address deployed) private view {
        bytes memory code = deployed.code;
        assertGt(code.length, 0);
        assertLe(code.length, 24_576);
        for (uint256 i; i < code.length; ++i) {
            uint8 op = uint8(code[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
                continue;
            }
            assertTrue(op != 0xf4 && op != 0xf2 && op != 0xff, "forbidden runtime opcode");
        }
    }
}
