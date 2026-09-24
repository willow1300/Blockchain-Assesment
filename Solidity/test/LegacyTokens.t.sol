// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

// Shared token interface. The 4 legacy contracts (0.5.17) can't be
// imported into a 0.8.20 test file, so we deploy them from their
// compiled artifacts with deployCode() and talk to them here.
interface Token {
    function totalSupply() external view returns (uint256);
    function balanceOf(address) external view returns (uint256);
    function allowance(address, address) external view returns (uint256);
    function transfer(address, uint256) external returns (bool);
    function approve(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
    function owner() external view returns (address);
}

contract LegacyTokensTest is Test {
    Token fixd;
    Token flex;
    Token fwd;
    Token myt;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    // solc 0.5.17 has no receive(), only the old fallback function,
    // so plain ETH transfers (2300 gas) revert on MyToken.
    // fund this contract so it can call with full gas instead.
    receive() external payable {}

    function setUp() public {
        vm.deal(address(this), 100 ether);
        fixd = Token(deployCode("FixedSupplyToken.sol:FixedSupplyToken"));
        flex = Token(
            deployCode(
                "FlexibleToken.sol:FlexibleToken",
                abi.encode("FLX", "Flexible", uint8(18), uint256(1000 ether))
            )
        );
        fwd = Token(deployCode("BitFwdToken.sol:BitFwdToken"));
        myt = Token(deployCode("MyToken.sol:MyToken"));
    }

    // -- FixedSupplyToken --

    function test_FixedSupply() public view {
        assertEq(fixd.totalSupply(), 1_000_000 ether);
        assertEq(fixd.balanceOf(address(this)), 1_000_000 ether);
    }

    function test_FixedTransfer() public {
        assertTrue(fixd.transfer(alice, 100 ether));
        assertEq(fixd.balanceOf(alice), 100 ether);
    }

    function test_FixedTransferRevertsToZero() public {
        vm.expectRevert();
        fixd.transfer(address(0), 1);
    }

    function test_FixedTransferRevertsWhenBroke() public {
        vm.expectRevert();
        fixd.transfer(alice, 2_000_000 ether);
    }

    function test_FixedApproveAndTransferFrom() public {
        assertTrue(fixd.approve(alice, 50 ether));
        assertEq(fixd.allowance(address(this), alice), 50 ether);
        vm.prank(alice);
        assertTrue(fixd.transferFrom(address(this), bob, 50 ether));
        assertEq(fixd.balanceOf(bob), 50 ether);
        assertEq(fixd.allowance(address(this), alice), 0);
    }

    function test_FixedApproveRevertsToZero() public {
        vm.expectRevert();
        fixd.approve(address(0), 1);
    }

    function test_FixedRejectsETH() public {
        (bool ok, ) = address(fixd).call{value: 1 ether}("");
        assertFalse(ok);
    }

    // -- FlexibleToken --

    function test_FlexMetadataAndLock() public {
        assertEq(flex.totalSupply(), 1000 ether);
        (bool ok, bytes memory ret) = address(flex).call(
            abi.encodeWithSignature("locked()")
        );
        assertTrue(ok && !abi.decode(ret, (bool)));

        (ok, ) = address(flex).call(
            abi.encodeWithSignature("setSymbol(string)", "NEW")
        );
        assertTrue(ok);
        (ok, ) = address(flex).call(abi.encodeWithSignature("lock()"));
        assertTrue(ok);

        // locked now, rename must fail
        (ok, ) = address(flex).call(
            abi.encodeWithSignature("setSymbol(string)", "NOPE")
        );
        assertFalse(ok);
    }

    function test_FlexOnlyOwnerCanRename() public {
        vm.prank(alice);
        (bool ok, ) = address(flex).call(
            abi.encodeWithSignature("setSymbol(string)", "HACK")
        );
        assertFalse(ok);
    }

    // -- BitFwdToken (mintable) --

    function test_FwdMintDisable() public {
        (bool ok, bytes memory ret) = address(fwd).call(
            abi.encodeWithSignature("mintable()")
        );
        assertTrue(ok && abi.decode(ret, (bool)));

        (ok, ) = address(fwd).call(
            abi.encodeWithSignature("mint(address,uint256)", alice, 500 ether)
        );
        assertTrue(ok);
        assertEq(fwd.balanceOf(alice), 500 ether);

        (ok, ) = address(fwd).call(abi.encodeWithSignature("disableMinting()"));
        assertTrue(ok);

        // closed now, mint must fail
        (ok, ) = address(fwd).call(
            abi.encodeWithSignature("mint(address,uint256)", alice, 1)
        );
        assertFalse(ok);
    }

    function test_FwdMintToZeroReverts() public {
        (bool ok, ) = address(fwd).call(
            abi.encodeWithSignature("mint(address,uint256)", address(0), 1)
        );
        assertFalse(ok);
    }

    function test_FwdOnlyOwnerMints() public {
        vm.prank(alice);
        (bool ok, ) = address(fwd).call(
            abi.encodeWithSignature("mint(address,uint256)", alice, 1)
        );
        assertFalse(ok);
    }
}
