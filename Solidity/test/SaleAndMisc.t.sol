// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/SavePrincessLeiaPeachRainbowVomitCatICOToken.sol" as LeiaFile;
import "../contracts/SeanTestToken.sol" as SeanFile;
import "../contracts/SafeMath.sol" as MathFile;

// MyToken (0.5.17) can't be imported here, so same artifact trick:
// deploy from compiled output, talk through a small interface.
interface Myt {
    function balanceOf(address) external view returns (uint256);
    function endDate() external view returns (uint256);
}

contract SaleTokensTest is Test {
    Myt myt;
    LeiaFile.SavePrincessLeiaPeachRainbowVomitCatICOToken leia;

    address alice = makeAddr("alice");

    // both sales need this contract able to receive ETH (withdraw test).
    receive() external payable {}

    function setUp() public {
        vm.deal(address(this), 100 ether);
        myt = Myt(payable(deployCode("MyToken.sol:MyToken")));
        leia = new LeiaFile.SavePrincessLeiaPeachRainbowVomitCatICOToken();
    }

    // -- MyToken --

    function test_MytBonusRate() public {
        uint256 before = myt.balanceOf(address(this));
        // low-level call forwards all gas, unlike a plain transfer.
        // the 0.5.x fallback needs that to run the mint logic.
        (bool ok, ) = address(myt).call{value: 1 ether}("");
        assertTrue(ok);
        assertEq(myt.balanceOf(address(this)) - before, 1200 ether);
    }

    function test_MytWindowCloses() public {
        vm.warp(myt.endDate() + 1);
        (bool ok, ) = address(myt).call{value: 1 ether}("");
        assertFalse(ok);
    }

    // -- LEIA --

    function test_LeiaBonusRateAndEscrow() public {
        vm.deal(alice, 2 ether);
        vm.prank(alice);
        (bool ok, ) = address(leia).call{value: 1 ether}("");
        assertTrue(ok);
        assertEq(leia.balanceOf(alice), 1200 ether);
        // archive refunded the buyer (free tokens). fixed keeps the ETH.
        assertEq(address(leia).balance, 1 ether);
    }

    function test_LeiaNormalRateAfterBonus() public {
        vm.warp(block.timestamp + 8 days);
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool ok, ) = address(leia).call{value: 1 ether}("");
        assertTrue(ok);
        assertEq(leia.balanceOf(alice), 1000 ether);
    }

    function test_LeiaZeroETHReverts() public {
        vm.prank(alice);
        (bool ok, ) = address(leia).call{value: 0}("");
        assertFalse(ok);
    }

    function test_LeiaClosesAfterEnd() public {
        vm.warp(block.timestamp + 30 days);
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool ok, ) = address(leia).call{value: 1 ether}("");
        assertFalse(ok);
    }

    function test_LeiaOwnerWithdraws() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool ok, ) = address(leia).call{value: 1 ether}("");
        assertTrue(ok);
        uint256 before = address(this).balance;
        leia.withdrawETH(1 ether);
        assertEq(address(this).balance - before, 1 ether);
    }

    function test_LeiaNonOwnerCannotWithdraw() public {
        vm.prank(alice);
        vm.expectRevert();
        leia.withdrawETH(1);
    }
}

contract MiscTokensTest is Test {
    SeanFile.SeanTestToken sean;
    address holder = address(0xB077883bF6154C9a24538A580Bd0d2F905D85384);

    function setUp() public {
        sean = new SeanFile.SeanTestToken();
    }

    function test_SeanHardcodedHolder() public view {
        // archive parity: everything to the fixed address, not deployer.
        assertEq(sean.totalSupply(), 100_000);
        assertEq(sean.balanceOf(holder), 100_000);
        assertEq(sean.balanceOf(address(this)), 0);
        assertEq(sean.decimals(), 0);
    }

    function test_SeanWholeUnits() public {
        // decimals = 0, so 1 means 1 whole token. no dust possible.
        address bob = makeAddr("bob");
        vm.prank(holder);
        assertTrue(sean.transfer(bob, 1));
        assertEq(sean.balanceOf(bob), 1);
    }

    function test_SeanRejectsETH() public {
        (bool ok, ) = address(sean).call{value: 1 ether}("");
        assertFalse(ok);
    }
}

contract SafeMathTest is Test {
    using MathFile.SafeMath for uint256;

    function test_AddSub() public pure {
        assertEq(uint256(2).add(3), 5);
        assertEq(uint256(5).sub(3), 2);
    }

    function test_SubReverts() public {
        vm.expectRevert();
        this.externalSub(1, 2);
    }

    function externalSub(uint256 a, uint256 b) external pure returns (uint256) {
        return a.sub(b);
    }

    function test_MulDiv() public pure {
        assertEq(uint256(3).mul(4), 12);
        assertEq(uint256(0).mul(999), 0);
        assertEq(uint256(12).div(4), 3);
    }

    function test_DivByZeroReverts() public {
        vm.expectRevert();
        this.externalDiv(1, 0);
    }

    function externalDiv(uint256 a, uint256 b) external pure returns (uint256) {
        return a.div(b);
    }
}
