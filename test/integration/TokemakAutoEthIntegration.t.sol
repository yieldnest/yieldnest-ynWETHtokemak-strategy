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

interface ISystemRegistry {
    function toke() external view returns (address);

    function weth() external view returns (address);

    function accToke() external view returns (address);

    function autoPoolRouter() external view returns (address);
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

    function convertToAssets(
        uint256 shares,
        uint256 totalAssets,
        uint256 totalSupply,
        uint8 round
    )
        external
        returns (uint256 assets);
    function totalAssets(uint8) external returns (uint256);
    function totalSupply() external returns (uint256);
}

abstract contract TokemakAutoEthAddresses {
    IAutopilotRouter public constant AUTOPILOT_ROUTER = IAutopilotRouter(0x39ff6d21204B919441d17bef61D19181870835A2);
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

        // Set Bob as allocator
        vm.startPrank(deployment.actors().ADMIN());
        deployment.strategy().grantRole(deployment.strategy().ALLOCATOR_ROLE(), BOB);
        vm.stopPrank();
    }

    function test_depositAndStake_success_using_router(uint256 depositAmount) public {
        depositAmount = bound(depositAmount, 0.1 ether, 10_000 ether);

        deal(deployment.baseAsset(), BOB, depositAmount);
        // Deposit as Bob
        vm.startPrank(BOB);
        IERC20(deployment.baseAsset()).approve(address(deployment.strategy()), depositAmount);
        deployment.strategy().deposit(depositAmount, BOB);
        vm.stopPrank();

        vm.startPrank(safe);
        uint256 initialWethBalanceOfSafe = IERC20(deployment.baseAsset()).balanceOf(safe);
        uint256 initialAutoEthBalanceOfSafe = IERC20(AUTO_ETH).balanceOf(safe);

        // need to check for sane minSharesOut in prod. is frontrunnable
        uint256 minSharesOut = IAutoPoolETH(AUTO_ETH).previewDeposit(depositAmount);

        //approve AUTOPILOT_ROUTER to pull tokens
        IERC20(deployment.baseAsset()).approve(address(AUTOPILOT_ROUTER), depositAmount);

        // deposit
        AUTOPILOT_ROUTER.pullToken(deployment.baseAsset(), depositAmount, address(AUTOPILOT_ROUTER));
        AUTOPILOT_ROUTER.approve(deployment.baseAsset(), AUTO_ETH, depositAmount);
        AUTOPILOT_ROUTER.deposit(AUTO_ETH, safe, depositAmount, minSharesOut);

        uint256 finalWethBalanceOfSafe = IERC20(deployment.baseAsset()).balanceOf(safe);
        uint256 finalAutoEthBalanceOfSafe = IERC20(AUTO_ETH).balanceOf(safe);

        assertEq(
            initialWethBalanceOfSafe - finalWethBalanceOfSafe,
            depositAmount,
            "WETH balance not as expected after deposit"
        );
        assertGe(
            finalAutoEthBalanceOfSafe,
            initialAutoEthBalanceOfSafe + minSharesOut,
            "AUTO_ETH balance not as expected after deposit"
        );

        uint256 autoEthBalanceReceivedBySafe = finalAutoEthBalanceOfSafe - initialAutoEthBalanceOfSafe;

        IERC20(AUTO_ETH).approve(address(AUTOPILOT_ROUTER), autoEthBalanceReceivedBySafe);

        // stake
        AUTOPILOT_ROUTER.pullToken(AUTO_ETH, autoEthBalanceReceivedBySafe, address(AUTOPILOT_ROUTER));
        AUTOPILOT_ROUTER.approve(AUTO_ETH, AUTOPOOL_MAIN_REWARDER, autoEthBalanceReceivedBySafe);
        AUTOPILOT_ROUTER.stakeVaultToken(AUTO_ETH, autoEthBalanceReceivedBySafe);

        assertEq(
            IAutoPoolMainRewarder(AUTOPOOL_MAIN_REWARDER).balanceOf(safe),
            autoEthBalanceReceivedBySafe,
            "AUTO_ETH balance not as expected after stake"
        );
        assertEq(IERC20(AUTO_ETH).balanceOf(safe), 0, "AUTO_ETH balance not as expected after stake");
        assertEq(
            IERC20(deployment.baseAsset()).balanceOf(safe),
            initialWethBalanceOfSafe - depositAmount,
            "WETH balance not as expected after stake"
        );
        vm.stopPrank();
    }

    function test_claimAutoPoolRewards_success_using_router(uint256 depositAmount) public {
        depositAmount = bound(depositAmount, 0.1 ether, 10_000 ether);

        deal(deployment.baseAsset(), BOB, depositAmount);
        // Deposit as Bob
        vm.startPrank(BOB);
        IERC20(deployment.baseAsset()).approve(address(deployment.strategy()), depositAmount);
        deployment.strategy().deposit(depositAmount, BOB);
        vm.stopPrank();

        vm.startPrank(safe);
        uint256 initialWethBalanceOfSafe = IERC20(deployment.baseAsset()).balanceOf(safe);
        uint256 initialAutoEthBalanceOfSafe = IERC20(AUTO_ETH).balanceOf(safe);

        // need to check for sane minSharesOut in prod. is frontrunnable
        uint256 minSharesOut = IAutoPoolETH(AUTO_ETH).previewDeposit(depositAmount);

        //approve AUTOPILOT_ROUTER to pull tokens
        IERC20(deployment.baseAsset()).approve(address(AUTOPILOT_ROUTER), depositAmount);

        // deposit
        AUTOPILOT_ROUTER.pullToken(deployment.baseAsset(), depositAmount, address(AUTOPILOT_ROUTER));
        AUTOPILOT_ROUTER.approve(deployment.baseAsset(), AUTO_ETH, depositAmount);
        AUTOPILOT_ROUTER.deposit(AUTO_ETH, safe, depositAmount, minSharesOut);

        uint256 finalWethBalanceOfSafe = IERC20(deployment.baseAsset()).balanceOf(safe);
        uint256 finalAutoEthBalanceOfSafe = IERC20(AUTO_ETH).balanceOf(safe);

        assertEq(
            initialWethBalanceOfSafe - finalWethBalanceOfSafe,
            depositAmount,
            "WETH balance not as expected after deposit"
        );
        assertGe(
            finalAutoEthBalanceOfSafe,
            initialAutoEthBalanceOfSafe + minSharesOut,
            "AUTO_ETH balance not as expected after deposit"
        );

        uint256 autoEthBalanceReceivedBySafe = finalAutoEthBalanceOfSafe - initialAutoEthBalanceOfSafe;

        IERC20(AUTO_ETH).approve(address(AUTOPILOT_ROUTER), autoEthBalanceReceivedBySafe);

        // stake
        AUTOPILOT_ROUTER.pullToken(AUTO_ETH, autoEthBalanceReceivedBySafe, address(AUTOPILOT_ROUTER));
        AUTOPILOT_ROUTER.approve(AUTO_ETH, AUTOPOOL_MAIN_REWARDER, autoEthBalanceReceivedBySafe);
        AUTOPILOT_ROUTER.stakeVaultToken(AUTO_ETH, autoEthBalanceReceivedBySafe);

        uint256 initialAutoPoolRewardsBalanceOfSafe = IAutoPoolMainRewarder(AUTOPOOL_MAIN_REWARDER).balanceOf(safe);
        assertEq(
            initialAutoPoolRewardsBalanceOfSafe,
            autoEthBalanceReceivedBySafe,
            "AUTO_ETH balance not as expected after stake"
        );
        assertEq(IERC20(AUTO_ETH).balanceOf(safe), 0, "AUTO_ETH balance not as expected after stake");
        assertEq(
            IERC20(deployment.baseAsset()).balanceOf(safe),
            initialWethBalanceOfSafe - depositAmount,
            "WETH balance not as expected after stake"
        );
        vm.stopPrank();

        skip(2 weeks);

        // TOKE should be received by safe because it's distributed every 2 weeks
        // Since that is off chain process, we can't add assertion here
        // https://docs.tokemak.xyz/using-the-app/app-guide/autopools/claim-incentives
        AUTOPILOT_ROUTER.claimAutopoolRewards(AUTO_ETH, AUTOPOOL_MAIN_REWARDER, safe);
        vm.stopPrank();
    }

    function test_unstakeAndRedeem_success_using_router(uint256 depositAmount) public {
        depositAmount = bound(depositAmount, 0.1 ether, 100_000 ether);

        deal(deployment.baseAsset(), BOB, depositAmount);
        // Deposit as Bob
        vm.startPrank(BOB);
        IERC20(deployment.baseAsset()).approve(address(deployment.strategy()), depositAmount);
        deployment.strategy().deposit(depositAmount, BOB);
        vm.stopPrank();

        vm.startPrank(safe);
        uint256 initialWethBalanceOfSafe = IERC20(deployment.baseAsset()).balanceOf(safe);
        uint256 initialAutoEthBalanceOfSafe = IERC20(AUTO_ETH).balanceOf(safe);

        // need to check for sane minSharesOut in prod. is frontrunnable
        uint256 minSharesOut = IAutoPoolETH(AUTO_ETH).previewDeposit(depositAmount);

        //approve AUTOPILOT_ROUTER to pull tokens
        IERC20(deployment.baseAsset()).approve(address(AUTOPILOT_ROUTER), depositAmount);

        // deposit
        AUTOPILOT_ROUTER.pullToken(deployment.baseAsset(), depositAmount, address(AUTOPILOT_ROUTER));
        AUTOPILOT_ROUTER.approve(deployment.baseAsset(), AUTO_ETH, depositAmount);
        AUTOPILOT_ROUTER.deposit(AUTO_ETH, safe, depositAmount, minSharesOut);

        uint256 finalWethBalanceOfSafe = IERC20(deployment.baseAsset()).balanceOf(safe);
        uint256 finalAutoEthBalanceOfSafe = IERC20(AUTO_ETH).balanceOf(safe);

        assertEq(
            initialWethBalanceOfSafe - finalWethBalanceOfSafe,
            depositAmount,
            "WETH balance not as expected after deposit"
        );
        assertGe(
            finalAutoEthBalanceOfSafe,
            initialAutoEthBalanceOfSafe + minSharesOut,
            "AUTO_ETH balance not as expected after deposit"
        );

        uint256 autoEthBalanceReceivedBySafe = finalAutoEthBalanceOfSafe - initialAutoEthBalanceOfSafe;

        IERC20(AUTO_ETH).approve(address(AUTOPILOT_ROUTER), autoEthBalanceReceivedBySafe);

        // stake
        AUTOPILOT_ROUTER.pullToken(AUTO_ETH, autoEthBalanceReceivedBySafe, address(AUTOPILOT_ROUTER));
        AUTOPILOT_ROUTER.approve(AUTO_ETH, AUTOPOOL_MAIN_REWARDER, autoEthBalanceReceivedBySafe);
        AUTOPILOT_ROUTER.stakeVaultToken(AUTO_ETH, autoEthBalanceReceivedBySafe);

        uint256 initialAutoPoolRewardsBalanceOfSafe = IAutoPoolMainRewarder(AUTOPOOL_MAIN_REWARDER).balanceOf(safe);
        assertEq(
            initialAutoPoolRewardsBalanceOfSafe,
            autoEthBalanceReceivedBySafe,
            "AUTO_ETH balance not as expected after stake"
        );
        assertEq(IERC20(AUTO_ETH).balanceOf(safe), 0, "AUTO_ETH balance not as expected after stake");
        assertEq(
            IERC20(deployment.baseAsset()).balanceOf(safe),
            initialWethBalanceOfSafe - depositAmount,
            "WETH balance not as expected after stake"
        );

        uint256 autoETHBalanceBeforeWithdraw = IERC20(AUTO_ETH).balanceOf(safe);
        // unstake
        AUTOPILOT_ROUTER.approve(AUTO_ETH, AUTOPOOL_MAIN_REWARDER, autoEthBalanceReceivedBySafe);
        AUTOPILOT_ROUTER.withdrawVaultToken(AUTO_ETH, AUTOPOOL_MAIN_REWARDER, minSharesOut, false);
        assertEq(
            IERC20(AUTO_ETH).balanceOf(safe) - autoETHBalanceBeforeWithdraw,
            autoEthBalanceReceivedBySafe,
            "AUTO_ETH balance not as expected after unstake"
        );

        // withdraw
        // need to check for sane minAssetsOut in prod. is frontrunnable
        IERC20(AUTO_ETH).approve(address(AUTOPILOT_ROUTER), autoEthBalanceReceivedBySafe);
        uint256 minAssetsOut = IAutoPoolETH(AUTO_ETH).previewRedeem(autoEthBalanceReceivedBySafe);
        AUTOPILOT_ROUTER.redeem(AUTO_ETH, safe, autoEthBalanceReceivedBySafe, minAssetsOut);
        assertApproxEqAbs(
            IERC20(deployment.baseAsset()).balanceOf(safe),
            initialWethBalanceOfSafe,
            1e18,
            "WETH balance not as expected after redeem"
        );
        assertEq(
            IERC20(AUTO_ETH).balanceOf(safe),
            initialAutoEthBalanceOfSafe,
            "AUTO_ETH balance not as expected after redeem"
        );

        vm.stopPrank();
    }

    function test_POC_Preview_Deposit_Preview_Redeem() public {
        uint256 depositAmount = 10_000 ether;

        uint256 shareAmountReceived = IAutoPoolETH(AUTO_ETH).previewDeposit(depositAmount);

        uint256 assetsReceivedFromShare = IAutoPoolETH(AUTO_ETH).previewRedeem(shareAmountReceived);

        console.log("depositAmount", depositAmount);
        console.log("shareAmountReceived", shareAmountReceived);
        console.log("assetsReceivedFromShare", assetsReceivedFromShare);
        console.log("difference", depositAmount - assetsReceivedFromShare);

        // for 100 ether, we are receiving 99.97 ether
        // for 500 ether, we are receiving 499.42 ether
        // for 1000 ether, we are receiving 963.34 ether
        // for 10000 ether, we are receiving 5692.02 ether
    }

    function test_POC_Convert_To_Assets() public {
        uint256 depositAmount = 10_000 ether;

        uint256 sharesReceived = IAutoPoolETH(AUTO_ETH).previewDeposit(depositAmount);

        uint256 totalAssets = IAutoPoolETH(AUTO_ETH).totalAssets(uint8(2));
        uint256 totalSupply = IAutoPoolETH(AUTO_ETH).totalSupply();

        uint256 maxReturnedAssets =
            IAutoPoolETH(AUTO_ETH).convertToAssets(sharesReceived, totalAssets, totalSupply, uint8(0));

        console.log("maxReturnedAssets", maxReturnedAssets);
        console.log("difference", depositAmount - maxReturnedAssets);

        // for 100 ether, we are pricing 99.997 ether
        // for 500 ether, we are pricing, 499.98 ether
        // for 1000 ether, we are pricing, 999.97 ether
        // for 10000 ether, we are pricing, 9999.76 ether
    }

    function test_depositAndRedeem_large_amount_using_api_routes() public {
        uint256 depositAmount = 2000 ether;
        uint256 slippageTolerance = 5e14; // 0.05%

        deal(deployment.baseAsset(), BOB, depositAmount);
        // Deposit as Bob
        vm.startPrank(BOB);
        IERC20(deployment.baseAsset()).approve(address(deployment.strategy()), depositAmount);
        deployment.strategy().deposit(depositAmount, BOB);
        vm.stopPrank();

        vm.startPrank(safe);
        uint256 initialWethBalanceOfSafe = IERC20(deployment.baseAsset()).balanceOf(safe);
        uint256 initialAutoEthBalanceOfSafe = IERC20(AUTO_ETH).balanceOf(safe);

        // need to check for sane minSharesOut in prod. is frontrunnable
        uint256 minSharesOut = IAutoPoolETH(AUTO_ETH).previewDeposit(depositAmount);

        //approve AUTOPILOT_ROUTER to pull tokens
        IERC20(deployment.baseAsset()).approve(address(AUTOPILOT_ROUTER), depositAmount);

        // deposit
        AUTOPILOT_ROUTER.pullToken(deployment.baseAsset(), depositAmount, address(AUTOPILOT_ROUTER));
        AUTOPILOT_ROUTER.approve(deployment.baseAsset(), AUTO_ETH, depositAmount);
        AUTOPILOT_ROUTER.deposit(AUTO_ETH, safe, depositAmount, minSharesOut);

        uint256 finalWethBalanceOfSafe = IERC20(deployment.baseAsset()).balanceOf(safe);
        uint256 finalAutoEthBalanceOfSafe = IERC20(AUTO_ETH).balanceOf(safe);

        assertEq(
            initialWethBalanceOfSafe - finalWethBalanceOfSafe,
            depositAmount,
            "WETH balance not as expected after deposit"
        );
        assertGe(
            finalAutoEthBalanceOfSafe,
            initialAutoEthBalanceOfSafe + minSharesOut,
            "AUTO_ETH balance not as expected after deposit"
        );

        uint256 autoEthBalanceReceivedBySafe = finalAutoEthBalanceOfSafe - initialAutoEthBalanceOfSafe;

        // redeem
        // need to check for sane minAssetsOut in prod. is frontrunnable
        IERC20(AUTO_ETH).approve(address(AUTOPILOT_ROUTER), autoEthBalanceReceivedBySafe);
        uint256 expectedWethBalance = depositAmount * (1e18 - slippageTolerance) / 1e18;
        bytes memory redeemWithRoutesCalldata =
            _fetchRedeemWithRoutesCalldata(safe, autoEthBalanceReceivedBySafe, expectedWethBalance);
        (bool success,) = address(AUTOPILOT_ROUTER).call(redeemWithRoutesCalldata);
        assertTrue(success, "Redeem failed");

        uint256 wethBalanceOfSafe = IERC20(deployment.baseAsset()).balanceOf(safe);
        assertApproxEqRel(
            wethBalanceOfSafe, initialWethBalanceOfSafe, 5e14, "WETH balance received should be within 0.05% slippage"
        );
        vm.stopPrank();
    }

    function _fetchRedeemWithRoutesCalldata(
        address sender,
        uint256 autoETHSharesAmount,
        uint256 minExpectedWETH
    )
        internal
        returns (bytes memory)
    {
        string[] memory inputs = new string[](5);
        inputs[0] = "node";
        inputs[1] = "test/scripts/tokemakSwapRoute.ts";
        inputs[2] = vm.toString(sender);
        inputs[3] = vm.toString(autoETHSharesAmount);
        inputs[4] = vm.toString(minExpectedWETH);

        bytes memory res = vm.ffi(inputs);
        return res;
    }
}
