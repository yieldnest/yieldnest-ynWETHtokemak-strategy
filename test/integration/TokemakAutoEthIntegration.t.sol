// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import { Test, console } from "forge-std/Test.sol";
import { DeployFlexStrategy } from "script/DeployFlexStrategy.s.sol";
import { FlexStrategy } from "src/FlexStrategy.sol";
import { AccountingModule } from "src/AccountingModule.sol";
import { AccountingToken } from "src/AccountingToken.sol";
import { IVault } from "@yieldnest-vault/interface/IVault.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { BaseScript } from "script/BaseScript.sol";

interface IAutoPoolMainRewarder {
    function balanceOf(address account) external view returns (uint256);

    function earned(address account) external view returns (uint256);
}

interface IAutopilotRouter {
    function approve(address token, address to, uint256 amount) external payable;

    function claimAutopoolRewards(address vault, address rewarder, address recipient) external payable;

    function deposit(
        address vault,
        address to,
        uint256 amount,
        uint256 minSharesOut
    )
        external
        payable
        returns (uint256 sharesOut);

    function pullToken(address token, uint256 amount, address recipient) external payable;

    function redeem(
        address vault,
        address to,
        uint256 shares,
        uint256 minAmountOut
    )
        external
        payable
        returns (uint256 amountOut);

    function stakeVaultToken(address vault, uint256 maxAmount) external payable returns (uint256);

    function withdrawVaultToken(
        address vault,
        address rewarder,
        uint256 maxAmount,
        bool claim
    )
        external
        payable
        returns (uint256);
}

interface IAutoPoolETH {
    /// @notice Simulates the effects of a deposit at the current block
    /// @param assets The amount of assets to deposit
    /// @return shares The amount of shares that would be minted
    function previewDeposit(uint256 assets) external returns (uint256 shares);

    /// @notice Simulates the effects of a redemption at the current block
    /// @param shares The amount of shares to redeem
    /// @return assets The amount of assets that would be withdrawn
    function previewRedeem(uint256 shares) external returns (uint256 assets);
}

abstract contract TokemakAutoEthAddresses {
    IAutopilotRouter public constant AUTOPILOT_ROUTER = IAutopilotRouter(0x37dD409f5e98aB4f151F4259Ea0CC13e97e8aE21);
    address public constant AUTO_ETH = 0x0A2b94F6871c1D7A32Fe58E1ab5e6deA2f114E56;
    address public constant AUTOPOOL_MAIN_REWARDER = 0x60882D6f70857606Cdd37729ccCe882015d1755E;
    address public constant TOKE = 0x2e9d63788249371f1DFC918a52f8d799F4a38C94;
}

contract TokemakAutoEthIntegration is TokemakAutoEthAddresses, Test {
    DeployFlexStrategy public deployment;
    address public DEPLOYER = address(0xd34db33f);
    address public BOB = address(0xb0b);
    address public safe;

    function setUp() public {
        deployment = new DeployFlexStrategy();
        deployment.setEnv(BaseScript.Env.TEST);
        deployment.run();

        safe = deployment.safe();

        deal(deployment.baseAsset(), BOB, 10 ether);

        // Set Bob as allocator
        vm.startPrank(deployment.actors().ADMIN());
        deployment.strategy().grantRole(deployment.strategy().ALLOCATOR_ROLE(), BOB);
        vm.stopPrank();

        // Deposit as Bob
        vm.startPrank(BOB);
        IERC20(deployment.baseAsset()).approve(address(deployment.strategy()), 10 ether);
        deployment.strategy().deposit(10 ether, BOB);
        vm.stopPrank();
    }

    function test_setup_success() public view {
        assertEq(deployment.strategy().balanceOf(BOB), 10 ether, "Bob should have 10 shares");
        assertEq(IERC20(deployment.baseAsset()).balanceOf(BOB), 0, "Bob should have 0 WETH");
        assertEq(IERC20(deployment.baseAsset()).balanceOf(safe), 10 ether, "Safe should have 10 WETH");
    }

    function test_depositAndStake_success() public {
        vm.startPrank(safe);
        uint256 deposit = 2 ether;
        uint256 initialWethBalance = IERC20(deployment.baseAsset()).balanceOf(safe);

        // need to check for sane minSharesOut in prod. is frontrunnable
        uint256 minSharesOut = IAutoPoolETH(AUTO_ETH).previewDeposit(deposit);

        //approve AUTOPILOT_ROUTER to pull tokens
        IERC20(deployment.baseAsset()).approve(address(AUTOPILOT_ROUTER), type(uint256).max);
        IERC20(AUTO_ETH).approve(address(AUTOPILOT_ROUTER), type(uint256).max);

        // deposit
        AUTOPILOT_ROUTER.pullToken(deployment.baseAsset(), deposit, address(AUTOPILOT_ROUTER));
        AUTOPILOT_ROUTER.approve(deployment.baseAsset(), AUTO_ETH, deposit);
        AUTOPILOT_ROUTER.deposit(AUTO_ETH, safe, deposit, minSharesOut);

        // stake
        AUTOPILOT_ROUTER.pullToken(AUTO_ETH, minSharesOut, address(AUTOPILOT_ROUTER));
        AUTOPILOT_ROUTER.approve(AUTO_ETH, AUTOPOOL_MAIN_REWARDER, minSharesOut);
        AUTOPILOT_ROUTER.stakeVaultToken(AUTO_ETH, minSharesOut);

        assertEq(IAutoPoolMainRewarder(AUTOPOOL_MAIN_REWARDER).balanceOf(safe), minSharesOut);
        assertEq(IERC20(AUTO_ETH).balanceOf(safe), 0);
        assertEq(IERC20(deployment.baseAsset()).balanceOf(safe), initialWethBalance - deposit);
        vm.stopPrank();
    }

    function test_claimAutoPoolRewards_success() public {
        vm.startPrank(safe);
        uint256 deposit = 2 ether;

        // need to check for sane minSharesOut in prod. is frontrunnable
        uint256 minSharesOut = IAutoPoolETH(AUTO_ETH).previewDeposit(deposit);

        //approve AUTOPILOT_ROUTER to pull tokens
        IERC20(deployment.baseAsset()).approve(address(AUTOPILOT_ROUTER), type(uint256).max);
        IERC20(AUTO_ETH).approve(address(AUTOPILOT_ROUTER), type(uint256).max);

        // deposit
        AUTOPILOT_ROUTER.pullToken(deployment.baseAsset(), deposit, address(AUTOPILOT_ROUTER));
        AUTOPILOT_ROUTER.approve(deployment.baseAsset(), AUTO_ETH, deposit);
        AUTOPILOT_ROUTER.deposit(AUTO_ETH, safe, deposit, minSharesOut);

        // stake
        AUTOPILOT_ROUTER.pullToken(AUTO_ETH, minSharesOut, address(AUTOPILOT_ROUTER));
        AUTOPILOT_ROUTER.approve(AUTO_ETH, AUTOPOOL_MAIN_REWARDER, minSharesOut);
        AUTOPILOT_ROUTER.stakeVaultToken(AUTO_ETH, minSharesOut);

        skip(3 days);

        AUTOPILOT_ROUTER.claimAutopoolRewards(AUTO_ETH, AUTOPOOL_MAIN_REWARDER, safe);

        vm.stopPrank();
    }

    function test_unstakeAndWithdraw_success() public {
        vm.startPrank(safe);
        uint256 deposit = 2 ether;

        // need to check for sane minSharesOut in prod. is frontrunnable
        uint256 minSharesOut = IAutoPoolETH(AUTO_ETH).previewDeposit(deposit);

        //approve AUTOPILOT_ROUTER to pull tokens
        IERC20(deployment.baseAsset()).approve(address(AUTOPILOT_ROUTER), type(uint256).max);
        IERC20(AUTO_ETH).approve(address(AUTOPILOT_ROUTER), type(uint256).max);

        // deposit
        AUTOPILOT_ROUTER.pullToken(deployment.baseAsset(), deposit, address(AUTOPILOT_ROUTER));
        AUTOPILOT_ROUTER.approve(deployment.baseAsset(), AUTO_ETH, deposit);
        AUTOPILOT_ROUTER.deposit(AUTO_ETH, safe, deposit, minSharesOut);

        // stake
        AUTOPILOT_ROUTER.pullToken(AUTO_ETH, minSharesOut, address(AUTOPILOT_ROUTER));
        AUTOPILOT_ROUTER.approve(AUTO_ETH, AUTOPOOL_MAIN_REWARDER, minSharesOut);
        AUTOPILOT_ROUTER.stakeVaultToken(AUTO_ETH, minSharesOut);

        uint256 shares = minSharesOut;
        uint256 wethBalance = IERC20(deployment.baseAsset()).balanceOf(safe);

        // unstake
        AUTOPILOT_ROUTER.withdrawVaultToken(AUTO_ETH, AUTOPOOL_MAIN_REWARDER, shares, false);
        assertEq(IERC20(AUTO_ETH).balanceOf(safe), shares);

        // withdraw
        // need to check for sane minAssetsOut in prod. is frontrunnable
        uint256 minAssetsOut = IAutoPoolETH(AUTO_ETH).previewRedeem(shares);
        AUTOPILOT_ROUTER.redeem(AUTO_ETH, safe, shares, minAssetsOut);
        assertEq(IERC20(deployment.baseAsset()).balanceOf(safe), minAssetsOut + wethBalance);
        assertEq(IERC20(AUTO_ETH).balanceOf(safe), 0);

        vm.stopPrank();
    }
}
