// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import { Test, console } from "forge-std/Test.sol";
import { DeployFlexStrategy } from "script/DeployFlexStrategy.s.sol";
import { FlexStrategy } from "src/FlexStrategy.sol";
import { AccountingModule } from "src/AccountingModule.sol";
import { AccountingToken } from "src/AccountingToken.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { BaseScript } from "script/BaseScript.sol";
import {IAutoPoolMainRewarder, ISystemRegistry, IAutopilotRouter, IAutoPoolETH, TokemakAutoEthAddresses, TokemakAutoEthIntegration} from "./TokemakAutoEthIntegration.t.sol";
import {MainnetContracts as MC} from "lib/yieldnest-vault/script/Contracts.sol";
import {MainnetActors} from "lib/yieldnest-vault/script/Actors.sol";
import {Vault} from "lib/yieldnest-vault/src/Vault.sol";
import {IERC4626} from "lib/yieldnest-vault/src/Common.sol";
import {YnETHxMockProvider} from "../mocks/YnETHxMockProvider.sol";
import {SafeRules, IVault} from "lib/yieldnest-vault/script/rules/SafeRules.sol";
import {BaseRules} from "lib/yieldnest-vault/script/rules/BaseRules.sol";

contract YnETHxIntegrationTest is TokemakAutoEthIntegration, MainnetActors {
    
    Vault public YnETHx;
    IERC20 public WETH;
    FlexStrategy public TOKAMAK_STRATEGY;
    YnETHxMockProvider public ynETHxMockProvider;

    function setUp() public override {
        super.setUp();
        YnETHx = Vault(payable(MC.YNETHX));
        WETH = IERC20(MC.WETH);
        TOKAMAK_STRATEGY = deployment.strategy();

        ynETHxMockProvider = new YnETHxMockProvider(address(TOKAMAK_STRATEGY));
        vm.startPrank(TIMELOCK);
        YnETHx.setProvider(address(ynETHxMockProvider));
        vm.stopPrank();

        vm.startPrank(TIMELOCK);
        YnETHx.addAsset(address(TOKAMAK_STRATEGY), false);
        vm.stopPrank();

        bytes4 approveSelector = bytes4(keccak256("approve(address,uint256)"));
        Vault.FunctionRule memory currentRule = YnETHx.getProcessorRule(address(WETH), approveSelector);
        address[] memory whitelist;

        if (currentRule.isActive) {
            // Get the current whitelist from the rule
            address[] memory currentWhitelist = currentRule.paramRules[0].allowList;
            // Initialize the new whitelist with size + 1
            whitelist = new address[](currentWhitelist.length + 1);

            for (uint256 i = 0; i < currentWhitelist.length; i++) {
                whitelist[i] = currentWhitelist[i];
            }
            whitelist[currentWhitelist.length] = address(TOKAMAK_STRATEGY);
        } else {
            whitelist = new address[](1);
            whitelist[0] = address(TOKAMAK_STRATEGY);
        }
        SafeRules.RuleParams memory approveRule = BaseRules.getApprovalRule(address(WETH), whitelist);

        vm.startPrank(TIMELOCK);
        YnETHx.setProcessorRule(approveRule.contractAddress, approveRule.funcSig, approveRule.rule);
        vm.stopPrank();

        address[] memory targets = new address[](2);
        bytes4[] memory functionSigs = new bytes4[](2);
        IVault.FunctionRule[] memory rules = new IVault.FunctionRule[](2);

        {
            SafeRules.RuleParams memory depositRule = BaseRules.getDepositRule(address(TOKAMAK_STRATEGY), address(YnETHx));
            // Set deposit rule values
            targets[0] = depositRule.contractAddress;
            functionSigs[0] = depositRule.funcSig;
            rules[0] = depositRule.rule;
        }

        {
            SafeRules.RuleParams memory withdrawRule = BaseRules.getWithdrawRule(address(TOKAMAK_STRATEGY), address(YnETHx));
            // Set withdraw rule values
            targets[1] = withdrawRule.contractAddress;
            functionSigs[1] = withdrawRule.funcSig;
            rules[1] = withdrawRule.rule;
        }

        vm.startPrank(TIMELOCK);
        YnETHx.setProcessorRules(targets, functionSigs, rules);
        vm.stopPrank();

        vm.startPrank(deployment.safe());
        WETH.approve(address(deployment.accountingModule()), type(uint256).max);
        vm.stopPrank();

        YnETHx.processAccounting();
    }

    function test_allocate_from_ynETHx_to_tokamak_strategy(uint256 depositAmount, uint256 allocationAmount) public {
        depositAmount = bound(depositAmount, 100 ether, 1000 ether);
        allocationAmount = bound(allocationAmount, 99 ether, depositAmount);

        depositToYnETHx(depositAmount);
        uint256 totalAssetsOfYnETHxBeforeAllocation = YnETHx.totalAssets();
        uint256 totalSupplyOfYnETHxBeforeAllocation = YnETHx.totalSupply();
        
        allocateFromYnETHxToTokamakStrategy(allocationAmount);

        uint256 totalAssetsOfYnETHxAfterAllocation = YnETHx.totalAssets();
        uint256 totalSupplyOfYnETHxAfterAllocation = YnETHx.totalSupply();

        assertEq(totalAssetsOfYnETHxAfterAllocation, totalAssetsOfYnETHxBeforeAllocation, "Total assets of ynETHx should not change after allocation");
        assertEq(totalSupplyOfYnETHxAfterAllocation, totalSupplyOfYnETHxBeforeAllocation, "Total supply of ynETHx should not change after allocation");
    }

    function test_allocate_from_ynETHx_to_tokamak_strategy_with_rewards(uint256 depositAmount, uint256 allocationAmount) public {
        depositAmount = bound(depositAmount, 100 ether, 1000 ether);
        allocationAmount = bound(allocationAmount, 100 ether, depositAmount);

        uint256 rewardAmount = 0.1 ether;

        test_allocate_from_ynETHx_to_tokamak_strategy(depositAmount, allocationAmount);

        uint256 totalAssetsOfYnETHxBeforeRewards = YnETHx.totalAssets();
        uint256 totalSupplyOfYnETHxBeforeRewards = YnETHx.totalSupply();

        vm.startPrank(safe);
        deal(address(WETH), safe, rewardAmount);
        WETH.transfer(address(TOKAMAK_STRATEGY), rewardAmount);
        deployment.accountingModule().processRewards(rewardAmount);
        vm.stopPrank();

        uint256 totalAssetsOfYnETHxAfterRewards = YnETHx.totalAssets();
        uint256 totalSupplyOfYnETHxAfterRewards = YnETHx.totalSupply();

        assertEq(totalAssetsOfYnETHxAfterRewards, totalAssetsOfYnETHxBeforeRewards + rewardAmount, "Total assets of ynETHx should increase by the reward amount");
        assertEq(totalSupplyOfYnETHxAfterRewards, totalSupplyOfYnETHxBeforeRewards, "Total supply of ynETHx should not change after rewards");

    }

    function test_allocate_from_ynETHx_to_tokamak_strategy_with_loss(uint256 depositAmount, uint256 allocationAmount) public {
        depositAmount = bound(depositAmount, 100 ether, 1000 ether);
        allocationAmount = bound(allocationAmount, 100 ether, depositAmount);

        uint256 lossAmount = 0.1 ether;

        test_allocate_from_ynETHx_to_tokamak_strategy(depositAmount, allocationAmount);

        uint256 totalAssetsOfYnETHxBeforeLoss = YnETHx.totalAssets();
        uint256 totalSupplyOfYnETHxBeforeLoss = YnETHx.totalSupply();

        vm.startPrank(safe);
        deal(address(WETH), safe, lossAmount);
        WETH.transfer(address(TOKAMAK_STRATEGY), lossAmount);
        deployment.accountingModule().processLosses(lossAmount);
        vm.stopPrank();

        uint256 totalAssetsOfYnETHxAfterLoss = YnETHx.totalAssets();
        uint256 totalSupplyOfYnETHxAfterLoss = YnETHx.totalSupply();

        assertEq(totalAssetsOfYnETHxAfterLoss, totalAssetsOfYnETHxBeforeLoss - lossAmount, "Total assets of ynETHx should decrease by the loss amount");
        assertEq(totalSupplyOfYnETHxAfterLoss, totalSupplyOfYnETHxBeforeLoss, "Total supply of ynETHx should not change after losses");

    }

    function test_withdraw_from_tokamak_strategy_to_ynETHx(uint256 depositAmount, uint256 allocationAmount, uint256 withdrawAmount) public {
        depositAmount = bound(depositAmount, 1 ether, 1000 ether);
        allocationAmount = bound(allocationAmount, 0.5 ether, depositAmount);
        withdrawAmount = bound(withdrawAmount, 0.5 ether, allocationAmount);

        depositAmount = 100 ether;
        allocationAmount = 50 ether;
        withdrawAmount = 25 ether;

        test_allocate_from_ynETHx_to_tokamak_strategy(depositAmount, allocationAmount);

        uint256 totalAssetsOfYnETHxBeforeWithdrawal = YnETHx.totalAssets();
        uint256 totalSupplyOfYnETHxBeforeWithdrawal = YnETHx.totalSupply();

        withdrawFromTokamakStrategyToYnETHx(withdrawAmount);

        uint256 totalAssetsOfYnETHxAfterWithdrawal = YnETHx.totalAssets();
        uint256 totalSupplyOfYnETHxAfterWithdrawal = YnETHx.totalSupply();

        assertEq(totalAssetsOfYnETHxAfterWithdrawal, totalAssetsOfYnETHxBeforeWithdrawal, "Total assets of ynETHx should not change after withdrawal");
        assertEq(totalSupplyOfYnETHxAfterWithdrawal, totalSupplyOfYnETHxBeforeWithdrawal, "Total supply of ynETHx should not change after withdrawal");
    }



    function depositToYnETHx(uint256 amount) public returns(uint256) {
        deal(address(WETH), BOB, amount);

        vm.startPrank(BOB);
        IERC20(WETH).approve(address(YnETHx), amount);
        uint256 sharesReceived = YnETHx.deposit(amount, BOB);
        vm.stopPrank();

        YnETHx.processAccounting();
        return sharesReceived;
    }

    function allocateFromYnETHxToTokamakStrategy(uint256 amount) public {

         address[] memory targets = new address[](2);
         targets[0] = address(WETH);
         targets[1] = address(TOKAMAK_STRATEGY);

         uint256[] memory values = new uint256[](2);
         values[0] = 0;
         values[1] = 0;

         bytes[] memory datas = new bytes[](2);
         datas[0] = abi.encodeWithSelector(IERC20.approve.selector, address(TOKAMAK_STRATEGY), amount);
         datas[1] = abi.encodeWithSelector(IERC4626.deposit.selector, amount, address(YnETHx));

         vm.startPrank(YnProcessor);
         YnETHx.processor(targets, values, datas);
         YnETHx.processAccounting();
         vm.stopPrank();
    }

    function withdrawFromTokamakStrategyToYnETHx(uint256 amount) public {
        address[] memory targets = new address[](1);
        targets[0] = address(TOKAMAK_STRATEGY);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory datas = new bytes[](1);  
        datas[0] = abi.encodeWithSelector(IERC4626.withdraw.selector, amount, address(YnETHx), address(YnETHx));

        vm.startPrank(YnProcessor);
        YnETHx.processor(targets, values, datas);
        YnETHx.processAccounting();
        vm.stopPrank();
    }
}