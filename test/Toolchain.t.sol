// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/src/Test.sol";

/// Stage 0 check: proves the toolchain works before any real code exists.
/// - the pinned compiler (0.8.37) compiles this file,
/// - the Solidity test runner finds and runs it,
/// - the clock can be moved forward, which the passport's date rules depend on
///   (an entry's event date may not be later than the moment it is recorded).
contract ToolchainTest is Test {
    function test_clock_can_be_moved_forward_by_30_days() public {
        uint256 start = block.timestamp;
        vm.warp(start + 30 days);
        assertEq(block.timestamp, start + 30 days);
    }
}
