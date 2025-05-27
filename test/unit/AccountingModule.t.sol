// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { TransparentUpgradeableProxy } from "@yieldnest-vault/Common.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import { MockStrategy } from "../mocks/MockStrategy.sol";
import { AccountingModule, IAccountingModule } from "../../src/AccountingModule.sol";
import { AccountingToken } from "../../src/AccountingToken.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

contract AccountingModuleTest is Test {
    address public ADMIN = address(0xd34db33f);
    address public BOB = address(0x0b0b);
    address public SAFE = address(0x1111);
    address public SAFE_MANAGER = address(0x54f3);
    address public ACCOUNTING_PROCESSOR = address(0x4cc7);
    MockERC20 public mockErc20;
    AccountingModule public accountingModule;
    AccountingToken public accountingToken;
    MockStrategy public mockStrategy;
    uint16 public constant TARGET_APY = 1000;
    uint16 public constant LOWER_BOUND = 1000;

    function setUp() public {
        mockErc20 = new MockERC20("MOCK", "MOCK", 18);
        mockStrategy = new MockStrategy();

        // create accounting token proxy
        AccountingToken accountingToken_impl = new AccountingToken(address(mockErc20));
        TransparentUpgradeableProxy accountingToken_tu = new TransparentUpgradeableProxy(
            address(accountingToken_impl),
            ADMIN,
            abi.encodeWithSelector(AccountingToken.initialize.selector, ADMIN, "NAME", "SYMBOL")
        );
        accountingToken = AccountingToken(payable(address(accountingToken_tu)));

        // create accounting module proxy
        AccountingModule accountingModule_impl = new AccountingModule(address(mockStrategy), address(mockErc20));
        TransparentUpgradeableProxy accountingModule_tu = new TransparentUpgradeableProxy(
            address(accountingModule_impl),
            ADMIN,
            abi.encodeWithSelector(
                AccountingModule.initialize.selector, ADMIN, SAFE, address(accountingToken), TARGET_APY, LOWER_BOUND
            )
        );
        accountingModule = AccountingModule(payable(address(accountingModule_tu)));

        vm.startPrank(ADMIN);
        accountingToken.setAccountingModule(address(accountingModule));
        mockStrategy.setAccountingModule(accountingModule);
        vm.stopPrank();

        vm.prank(BOB);
        mockErc20.mint(type(uint128).max);

        vm.prank(SAFE);
        mockErc20.approve(address(accountingModule), type(uint256).max);
    }

    function test_setup_success() public view {
        assertEq(accountingToken.name(), "NAME");
        assertEq(accountingToken.symbol(), "SYMBOL");
        assertEq(accountingToken.decimals(), 18);
        assertEq(accountingToken.accountingModule(), address(accountingModule));
        assertEq(accountingToken.TRACKED_ASSET(), address(mockErc20));
        assertEq(accountingModule.BASE_ASSET(), address(mockErc20));
        assertEq(address(accountingModule.accountingToken()), address(accountingToken));
        assertEq(accountingModule.targetApy(), TARGET_APY);
        assertEq(accountingModule.lowerBound(), LOWER_BOUND);
    }

    function test_deposit_revertIfNotStrategy() public {
        vm.expectRevert(IAccountingModule.NotStrategy.selector);
        vm.prank(BOB);
        accountingModule.deposit(20e18);
    }

    function test_deposit_success() public {
        vm.startPrank(BOB);
        uint256 deposit = 20e18;
        mockErc20.approve(address(mockStrategy), type(uint256).max);
        mockStrategy.deposit(deposit);

        // assertEq(accountingToken.balanceOf(address(mockStrategy)), deposit);
    }

    function testFuzz_deposit(uint128 amount) public {
        vm.startPrank(BOB);
        uint256 deposit = amount;
        mockErc20.approve(address(mockStrategy), type(uint256).max);
        mockStrategy.deposit(deposit);
        assertEq(accountingToken.balanceOf(address(mockStrategy)), deposit);
    }

    function test_withdraw_revertIfNotStrategy() public {
        vm.expectRevert(IAccountingModule.NotStrategy.selector);
        vm.prank(BOB);
        accountingModule.withdraw(20e18);
    }

    function test_withdraw_success() public {
        vm.startPrank(BOB);
        uint256 deposit = 20e18;
        mockErc20.approve(address(mockStrategy), type(uint256).max);
        mockStrategy.deposit(deposit);

        uint256 bobBefore = mockErc20.balanceOf(BOB);
        uint256 withdraw = 10e18;
        mockStrategy.withdraw(withdraw);

        assertEq(accountingToken.balanceOf(address(mockStrategy)), deposit - withdraw);
        assertEq(mockErc20.balanceOf(BOB) - bobBefore, withdraw);
    }

    function testFuzz_withdraw(uint96 amount) public {
        vm.startPrank(BOB);
        uint256 deposit = type(uint128).max;
        mockErc20.approve(address(mockStrategy), type(uint256).max);
        mockStrategy.deposit(deposit);

        uint256 bobBefore = mockErc20.balanceOf(BOB);
        uint256 withdraw = amount;
        mockStrategy.withdraw(withdraw);

        assertEq(accountingToken.balanceOf(address(mockStrategy)), deposit - withdraw);
        assertEq(mockErc20.balanceOf(BOB) - bobBefore, withdraw);
    }

    function test_processRewards_revertIfNoAccountingProcessorRole() public {
        vm.startPrank(BOB);
        uint256 deposit = 20e18;
        mockErc20.approve(address(mockStrategy), type(uint256).max);
        mockStrategy.deposit(deposit);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                BOB,
                accountingModule.ACCOUNTING_PROCESSOR_ROLE()
            )
        );
        accountingModule.processRewards(1e6);
    }

    function test_processRewards_revertIfTvlTooLow() public {
        vm.startPrank(ADMIN);
        accountingModule.grantRole(accountingModule.ACCOUNTING_PROCESSOR_ROLE(), ACCOUNTING_PROCESSOR);
        vm.startPrank(BOB);
        uint256 deposit = 1e6;
        mockErc20.approve(address(mockStrategy), type(uint256).max);
        mockStrategy.deposit(deposit);

        vm.startPrank(ACCOUNTING_PROCESSOR);
        vm.expectRevert(IAccountingModule.TvlTooLow.selector);
        accountingModule.processRewards(1e6);
    }

    function test_processRewards_revertIfUpperBoundExceed() public {
        vm.startPrank(ADMIN);
        accountingModule.grantRole(accountingModule.ACCOUNTING_PROCESSOR_ROLE(), ACCOUNTING_PROCESSOR);

        vm.startPrank(BOB);
        uint256 deposit = 20e18;
        mockErc20.approve(address(mockStrategy), type(uint256).max);
        mockStrategy.deposit(deposit);

        vm.startPrank(ACCOUNTING_PROCESSOR);
        vm.expectRevert(IAccountingModule.AccountingLimitsExceeded.selector);
        accountingModule.processRewards(deposit);
    }

    function test_processRewards_revertIfTooEarly() public {
        vm.startPrank(ADMIN);
        accountingModule.grantRole(accountingModule.ACCOUNTING_PROCESSOR_ROLE(), ACCOUNTING_PROCESSOR);

        vm.startPrank(BOB);
        uint256 deposit = 20e18;
        mockErc20.approve(address(mockStrategy), type(uint256).max);
        mockStrategy.deposit(deposit);

        vm.startPrank(ACCOUNTING_PROCESSOR);
        accountingModule.processRewards(1e6);

        vm.expectRevert(IAccountingModule.TooEarly.selector);
        accountingModule.processRewards(1e6);

        skip(3601);
        accountingModule.processRewards(1e6);
    }

    function test_processRewards_success() public {
        vm.startPrank(ADMIN);
        accountingModule.grantRole(accountingModule.ACCOUNTING_PROCESSOR_ROLE(), ACCOUNTING_PROCESSOR);

        vm.startPrank(BOB);
        uint256 deposit = 20e18;
        mockErc20.approve(address(mockStrategy), type(uint256).max);
        mockStrategy.deposit(deposit);

        vm.startPrank(ACCOUNTING_PROCESSOR);
        accountingModule.processRewards(1e6);
        assertEq(accountingToken.balanceOf(address(mockStrategy)), deposit + 1e6);

        skip(3601);
        accountingModule.processRewards(1e6);
        assertEq(accountingToken.balanceOf(address(mockStrategy)), deposit + 1e6 + 1e6);
    }

    function testFuzz_processRewards(uint96 processedAmount) public {
        vm.startPrank(ADMIN);
        accountingModule.grantRole(accountingModule.ACCOUNTING_PROCESSOR_ROLE(), ACCOUNTING_PROCESSOR);

        uint256 supply = 10_000_000e18;
        vm.assume(
            processedAmount
                <= (accountingModule.targetApy() * supply / accountingModule.DIVISOR() / accountingModule.YEAR())
        );

        vm.startPrank(BOB);
        mockErc20.approve(address(mockStrategy), type(uint256).max);
        mockStrategy.deposit(supply);

        vm.startPrank(ACCOUNTING_PROCESSOR);
        accountingModule.processRewards(processedAmount);
        assertEq(accountingToken.balanceOf(address(mockStrategy)), supply + processedAmount);
    }

    function test_processLosses_revertIfNoAccountingProcessorRole() public {
        vm.startPrank(ADMIN);
        accountingModule.grantRole(accountingModule.ACCOUNTING_PROCESSOR_ROLE(), ACCOUNTING_PROCESSOR);

        vm.startPrank(BOB);
        uint256 deposit = 20e18;
        mockErc20.approve(address(mockStrategy), type(uint256).max);
        mockStrategy.deposit(deposit);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                BOB,
                accountingModule.ACCOUNTING_PROCESSOR_ROLE()
            )
        );
        accountingModule.processLosses(1e6);
    }

    function test_processLosses_revertIfTvlTooLow() public {
        vm.startPrank(ADMIN);
        accountingModule.grantRole(accountingModule.ACCOUNTING_PROCESSOR_ROLE(), ACCOUNTING_PROCESSOR);

        vm.startPrank(BOB);
        uint256 deposit = 1e6;
        mockErc20.approve(address(mockStrategy), type(uint256).max);
        mockStrategy.deposit(deposit);

        vm.startPrank(ACCOUNTING_PROCESSOR);
        vm.expectRevert(IAccountingModule.TvlTooLow.selector);
        accountingModule.processLosses(1e6);
    }

    function test_processLosses_revertIfLowerBoundExceed() public {
        vm.startPrank(ADMIN);
        accountingModule.grantRole(accountingModule.ACCOUNTING_PROCESSOR_ROLE(), ACCOUNTING_PROCESSOR);

        vm.startPrank(BOB);
        uint256 deposit = 20e18;
        mockErc20.approve(address(mockStrategy), type(uint256).max);
        mockStrategy.deposit(deposit);

        vm.startPrank(ACCOUNTING_PROCESSOR);
        vm.expectRevert(IAccountingModule.AccountingLimitsExceeded.selector);
        accountingModule.processLosses(deposit);
    }

    function test_processLosses_revertIfTooEarly() public {
        vm.startPrank(ADMIN);
        accountingModule.grantRole(accountingModule.ACCOUNTING_PROCESSOR_ROLE(), ACCOUNTING_PROCESSOR);

        vm.startPrank(BOB);
        uint256 deposit = 20e18;
        mockErc20.approve(address(mockStrategy), type(uint256).max);
        mockStrategy.deposit(deposit);

        vm.startPrank(ACCOUNTING_PROCESSOR);
        accountingModule.processLosses(1e6);

        vm.expectRevert(IAccountingModule.TooEarly.selector);
        accountingModule.processLosses(1e6);

        skip(3601);
        accountingModule.processLosses(1e6);
    }

    function test_processLosses_success() public {
        vm.startPrank(ADMIN);
        accountingModule.grantRole(accountingModule.ACCOUNTING_PROCESSOR_ROLE(), ACCOUNTING_PROCESSOR);

        vm.startPrank(BOB);
        uint256 deposit = 20e18;
        mockErc20.approve(address(mockStrategy), type(uint256).max);
        mockStrategy.deposit(deposit);

        vm.startPrank(ACCOUNTING_PROCESSOR);
        accountingModule.processLosses(1e6);
        assertEq(accountingToken.balanceOf(address(mockStrategy)), deposit - 1e6);

        skip(3601);
        accountingModule.processLosses(1e6);
        assertEq(accountingToken.balanceOf(address(mockStrategy)), deposit - 1e6 - 1e6);
    }

    function testFuzz_processLosses(uint96 processedAmount) public {
        vm.startPrank(ADMIN);
        accountingModule.grantRole(accountingModule.ACCOUNTING_PROCESSOR_ROLE(), ACCOUNTING_PROCESSOR);

        uint256 supply = 10_000_000e18;
        vm.assume(processedAmount <= (supply * accountingModule.lowerBound() / accountingModule.DIVISOR()));

        vm.startPrank(BOB);
        mockErc20.approve(address(mockStrategy), type(uint256).max);
        mockStrategy.deposit(supply);

        vm.startPrank(ACCOUNTING_PROCESSOR);
        accountingModule.processLosses(processedAmount);
        assertEq(accountingToken.balanceOf(address(mockStrategy)), supply - processedAmount);
    }

    function test_setTargetApy_revertIfNoSafeManagerRole() public {
        vm.startPrank(BOB);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, BOB, accountingModule.SAFE_MANAGER_ROLE()
            )
        );
        accountingModule.setTargetApy(5000);
    }

    function test_setTargetApy_revertIfExceedDivisor() public {
        vm.startPrank(ADMIN);
        accountingModule.grantRole(accountingModule.SAFE_MANAGER_ROLE(), SAFE_MANAGER);
        vm.startPrank(SAFE_MANAGER);

        accountingModule.setTargetApy(1e4);

        vm.expectRevert(IAccountingModule.InvariantViolation.selector);
        accountingModule.setTargetApy(10_001);
    }

    function test_setTargetApy_success() public {
        vm.startPrank(ADMIN);
        accountingModule.grantRole(accountingModule.SAFE_MANAGER_ROLE(), SAFE_MANAGER);
        vm.startPrank(SAFE_MANAGER);

        accountingModule.setTargetApy(2000);
        assertEq(accountingModule.targetApy(), 2000);
    }

    function test_setLowerBound_revertIfNoSafeManagerRole() public {
        vm.startPrank(BOB);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, BOB, accountingModule.SAFE_MANAGER_ROLE()
            )
        );
        accountingModule.setLowerBound(5000);
    }

    function test_setLowerBound_revertIfExceedDivisor() public {
        vm.startPrank(ADMIN);
        accountingModule.grantRole(accountingModule.SAFE_MANAGER_ROLE(), SAFE_MANAGER);
        vm.startPrank(SAFE_MANAGER);

        vm.expectRevert(IAccountingModule.InvariantViolation.selector);
        accountingModule.setLowerBound(1e4);
    }

    function test_setLowerBound_success() public {
        vm.startPrank(ADMIN);
        accountingModule.grantRole(accountingModule.SAFE_MANAGER_ROLE(), SAFE_MANAGER);
        vm.startPrank(SAFE_MANAGER);

        accountingModule.setLowerBound(2000);
        assertEq(accountingModule.lowerBound(), 2000);
    }

    function test_setCooldownSeconds_revertIfNoSafeManagerRole() public {
        vm.startPrank(BOB);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, BOB, accountingModule.SAFE_MANAGER_ROLE()
            )
        );
        accountingModule.setCooldownSeconds(5000);
    }

    function test_setCooldownSeconds_success() public {
        vm.startPrank(ADMIN);
        accountingModule.grantRole(accountingModule.SAFE_MANAGER_ROLE(), SAFE_MANAGER);
        vm.startPrank(SAFE_MANAGER);

        accountingModule.setCooldownSeconds(5000);
        assertEq(accountingModule.cooldownSeconds(), 5000);
    }

    function test_setSafeAddress_revertIfNoSafeManagerRole() public {
        vm.startPrank(BOB);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, BOB, accountingModule.SAFE_MANAGER_ROLE()
            )
        );
        accountingModule.setSafeAddress(BOB);
    }

    function test_setSafeAddress_success() public {
        vm.startPrank(ADMIN);
        accountingModule.grantRole(accountingModule.SAFE_MANAGER_ROLE(), SAFE_MANAGER);
        vm.startPrank(SAFE_MANAGER);

        accountingModule.setSafeAddress(BOB);
        assertEq(accountingModule.safe(), BOB);
    }
}
