// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import { Test, console } from "forge-std/Test.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import { TransparentUpgradeableProxy } from "@yieldnest-vault/Common.sol";
import { AccountingToken } from "../../src/AccountingToken.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { MockAccountingModule } from "../mocks/MockAccountingModule.sol";

contract AccountingTokenTest is Test {
    address public ADMIN = address(0xd34db33f);
    address public BOB = address(0x0b0b);

    MockERC20 public mockErc20;
    MockERC20 public mockErc20e6;
    AccountingToken public accountingToken;
    MockAccountingModule public accountingModule = new MockAccountingModule();

    function setUp() public {
        mockErc20 = new MockERC20("MOCK", "MOCK", 18);
        mockErc20e6 = new MockERC20("MOCK", "MOCK", 6);

        AccountingToken accountingToken_impl = new AccountingToken(address(mockErc20));
        TransparentUpgradeableProxy accountingToken_tu = new TransparentUpgradeableProxy(
            address(accountingToken_impl),
            ADMIN,
            abi.encodeWithSelector(AccountingToken.initialize.selector, ADMIN, "NAME", "SYMBOL")
        );
        accountingToken = AccountingToken(payable(address(accountingToken_tu)));

        accountingModule.setAccountingToken(address(accountingToken));
        vm.prank(ADMIN);
        accountingToken.setAccountingModule(address(accountingModule));
    }

    function test_setup_success() public view {
        assertEq(accountingToken.name(), "NAME");
        assertEq(accountingToken.symbol(), "SYMBOL");
        assertEq(accountingToken.decimals(), 18);
    }

    function test_accountingToken_decimal_inherit_baseAsset() public {
        AccountingToken implementation2 = new AccountingToken(address(mockErc20e6));
        TransparentUpgradeableProxy tu2 = new TransparentUpgradeableProxy(
            address(implementation2),
            ADMIN,
            abi.encodeWithSelector(AccountingToken.initialize.selector, ADMIN, "NAME6", "SYMBOL6")
        );
        accountingToken = AccountingToken(payable(address(tu2)));
        assertEq(accountingToken.name(), "NAME6");
        assertEq(accountingToken.symbol(), "SYMBOL6");
        assertEq(accountingToken.decimals(), 6);
    }

    function test_mintTo_revertIfNotAccounting() public {
        vm.expectRevert(AccountingToken.Unauthorized.selector);
        accountingToken.mintTo(ADMIN, 1e18);
    }

    function test_mintTo_success() public {
        vm.startPrank(address(accountingModule));
        accountingToken.mintTo(ADMIN, 1e18);
        assertEq(accountingToken.balanceOf(ADMIN), 1e18);
    }

    function test_burnFrom_revertIfNotAccounting() public {
        vm.prank(address(accountingModule));
        accountingToken.mintTo(ADMIN, 1e18);
        vm.stopPrank();
        vm.expectRevert(AccountingToken.Unauthorized.selector);
        accountingToken.burnFrom(ADMIN, 1e18);
    }

    function test_burnFrom_success() public {
        vm.startPrank(address(accountingModule));
        accountingToken.mintTo(ADMIN, 1e18);
        accountingToken.burnFrom(ADMIN, 1e18);
        assertEq(accountingToken.balanceOf(ADMIN), 0);
    }

    function test_transferFrom_revert() public {
        vm.startPrank(address(accountingModule));
        accountingToken.mintTo(ADMIN, 1e18);
        vm.expectRevert(AccountingToken.NotAllowed.selector);
        accountingToken.transferFrom(ADMIN, BOB, 1e18);
    }

    function test_transfer_revert() public {
        vm.startPrank(address(accountingModule));
        accountingToken.mintTo(ADMIN, 1e18);
        vm.expectRevert(AccountingToken.NotAllowed.selector);
        accountingToken.transfer(BOB, 1e18);
    }

    function test_setAccountingModule_revertIfNoDefaultAdminRole() public {
        vm.startPrank(BOB);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, BOB, accountingToken.DEFAULT_ADMIN_ROLE()
            )
        );
        accountingToken.setAccountingModule(BOB);
    }

    function test_setAccountingModule_success() public {
        MockAccountingModule mockAccountingModule2 = new MockAccountingModule();
        mockAccountingModule2.setAccountingToken(address(accountingToken));
        vm.startPrank(ADMIN);
        accountingToken.setAccountingModule(address(mockAccountingModule2));
        assertEq(accountingToken.accountingModule(), address(mockAccountingModule2));
    }

    function test_setAccountingModule_revertIfAccountingTokenMismatch() public {
        MockAccountingModule mockAccountingModule2 = new MockAccountingModule();
        mockAccountingModule2.setAccountingToken(address(mockAccountingModule2));
        vm.startPrank(ADMIN);
        vm.expectRevert(AccountingToken.AccountingTokenMismatch.selector);
        accountingToken.setAccountingModule(address(mockAccountingModule2));
    }
}
