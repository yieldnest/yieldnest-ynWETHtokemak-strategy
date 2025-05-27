// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { IVault } from "@yieldnest-vault/interface/IVault.sol";
import { Ownable } from "openzeppelin-contracts/contracts/access/Ownable.sol";
import { BaseScript } from "script/BaseScript.sol";
import { MainnetActors } from "@yieldnest-vault-script/Actors.sol";
import { RolesVerification } from "./RolesVerification.sol";

// forge script VerifyFlexStrategy --rpc-url <MAINNET_RPC_URL>
contract VerifyFlexStrategy is BaseScript, Test {
    function symbol() public pure override returns (string memory) {
        return "ynFlexEth";
    }

    function run() public {
        _loadDeployment(deploymentEnv);
        _setup();

        verify();
    }

    function _verifyDeploymentParams() internal view virtual {
        assertEq(strategy.name(), "YieldNest Flex Strategy", "name is invalid");
        assertEq(strategy.symbol(), "ynFlexEth", "symbol is invalid");
        assertEq(strategy.decimals(), 18, "decimals is invalid");
        RolesVerification.verifyRole(
            strategy, allocator, strategy.ALLOCATOR_ROLE(), true, "parent vault has allocator role"
        );
        assertEq(accountingModule.targetApy(), 1000, "targetApy is not set");
        assertEq(accountingModule.lowerBound(), 1000, "lowerBound is not set");
        RolesVerification.verifyRole(
            accountingModule,
            safe,
            accountingModule.ACCOUNTING_PROCESSOR_ROLE(),
            true,
            "safe has accounting processor role"
        );
    }

    function verify() internal view virtual {
        _verifyDeploymentParams();

        assertNotEq(address(strategy), address(0), "strategy is not set");
        assertNotEq(address(strategyImplementation), address(0), "strategy implementation is not set");
        assertNotEq(address(strategyProxyAdmin), address(0), "strategy proxy admin is not set");

        assertEq(address(strategy.accountingModule()), address(accountingModule), "strategy.accountingModule() not set");
        assertEq(
            address(accountingToken.accountingModule()),
            address(accountingModule),
            "accountingToken.accountingModule() not set"
        );
        assertEq(
            address(accountingModule.accountingToken()),
            address(accountingToken),
            "accountingModule.accountingToken() not set"
        );
        assertEq(
            address(accountingModule.STRATEGY()),
            address(strategy),
            "accountingModule.STRATEGY() does not match strategy address"
        );
        assertEq(
            address(accountingToken.TRACKED_ASSET()),
            baseAsset,
            "accountingToken.TRACKED_ASSET() does not match base asset"
        );

        assertNotEq(address(rateProvider), address(0), "provider is invalid");
        assertEq(strategy.provider(), address(rateProvider), "provider is invalid");

        assertTrue(strategy.getHasAllocator(), "has allocator is invalid");
        assertEq(strategy.countNativeAsset(), false, "count native asset is invalid");
        assertEq(strategy.alwaysComputeTotalAssets(), false, "always compute total assets is invalid");

        address[] memory assets = strategy.getAssets();
        assertEq(assets.length, 1, "assets length is invalid");
        assertEq(assets[0], baseAsset, "assets[0] is invalid");
        assertFalse(strategy.paused(), "paused is invalid");

        RolesVerification.verifyDefaultRoles(strategy, accountingModule, accountingToken, timelock, actors);
        RolesVerification.verifyTemporaryRoles(strategy, accountingModule, accountingToken, deployer);
        RolesVerification.verifyRole(
            timelock,
            MainnetActors(address(actors)).YnSecurityCouncil(),
            timelock.PROPOSER_ROLE(),
            true,
            "proposer role for timelock is YnSecurityCouncil"
        );
        RolesVerification.verifyRole(
            timelock,
            MainnetActors(address(actors)).YnSecurityCouncil(),
            timelock.EXECUTOR_ROLE(),
            true,
            "executor role for timelock is YnSecurityCouncil"
        );
        RolesVerification.verifyRole(
            strategy,
            MainnetActors(address(actors)).YnBootstrapper(),
            strategy.ALLOCATOR_ROLE(),
            true,
            "bootstrapper has allocator role"
        );

        assertGe(timelock.getMinDelay(), minDelay, "min delay is invalid");
        assertEq(Ownable(strategyProxyAdmin).owner(), address(timelock), "proxy admin owner is invalid");
    }
}
