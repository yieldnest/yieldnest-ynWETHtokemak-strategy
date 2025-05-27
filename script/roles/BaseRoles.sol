// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.28;

import { IActors } from "@yieldnest-vault-script/Actors.sol";
import { FlexStrategy } from "src/FlexStrategy.sol";
import { AccountingModule } from "src/AccountingModule.sol";
import { AccountingToken } from "src/AccountingToken.sol";

library BaseRoles {
    function configureDefaultRoles(
        FlexStrategy strategy,
        AccountingModule accountingModule,
        AccountingToken accountingToken,
        address timelock,
        IActors actors
    )
        internal
    {
        // set admin roles
        strategy.grantRole(strategy.DEFAULT_ADMIN_ROLE(), actors.ADMIN());
        strategy.grantRole(strategy.PROCESSOR_ROLE(), actors.PROCESSOR());
        strategy.grantRole(strategy.PAUSER_ROLE(), actors.PAUSER());
        strategy.grantRole(strategy.UNPAUSER_ROLE(), actors.UNPAUSER());

        // set timelock roles
        strategy.grantRole(strategy.PROVIDER_MANAGER_ROLE(), timelock);
        strategy.grantRole(strategy.ASSET_MANAGER_ROLE(), timelock);
        strategy.grantRole(strategy.BUFFER_MANAGER_ROLE(), timelock);
        strategy.grantRole(strategy.PROCESSOR_MANAGER_ROLE(), timelock);
        strategy.grantRole(strategy.ALLOCATOR_MANAGER_ROLE(), timelock);
        accountingModule.grantRole(accountingModule.SAFE_MANAGER_ROLE(), timelock);
        accountingModule.grantRole(accountingModule.DEFAULT_ADMIN_ROLE(), timelock);
        accountingToken.grantRole(accountingToken.DEFAULT_ADMIN_ROLE(), timelock);
    }

    function configureDefaultRolesStrategy(
        FlexStrategy strategy,
        AccountingModule accountingModule,
        AccountingToken accountingToken,
        address timelock,
        IActors actors
    )
        internal
    {
        configureDefaultRoles(strategy, accountingModule, accountingToken, timelock, actors);
    }

    function configureTemporaryRoles(
        FlexStrategy strategy,
        AccountingModule accountingModule,
        AccountingToken accountingToken,
        address deployer
    )
        internal
    {
        strategy.grantRole(strategy.DEFAULT_ADMIN_ROLE(), deployer);
        strategy.grantRole(strategy.PROCESSOR_MANAGER_ROLE(), deployer);
        strategy.grantRole(strategy.BUFFER_MANAGER_ROLE(), deployer);
        strategy.grantRole(strategy.PROVIDER_MANAGER_ROLE(), deployer);
        strategy.grantRole(strategy.ASSET_MANAGER_ROLE(), deployer);
        strategy.grantRole(strategy.UNPAUSER_ROLE(), deployer);
        strategy.grantRole(strategy.ALLOCATOR_MANAGER_ROLE(), deployer);
        accountingToken.grantRole(accountingToken.DEFAULT_ADMIN_ROLE(), deployer);
        accountingModule.grantRole(accountingModule.DEFAULT_ADMIN_ROLE(), deployer);
    }

    function configureTemporaryRolesStrategy(
        FlexStrategy strategy,
        AccountingModule accountingModule,
        AccountingToken accountingToken,
        address deployer
    )
        internal
    {
        configureTemporaryRoles(strategy, accountingModule, accountingToken, deployer);
    }

    function renounceTemporaryRoles(
        FlexStrategy strategy,
        AccountingModule accountingModule,
        AccountingToken accountingToken,
        address deployer
    )
        internal
    {
        strategy.renounceRole(strategy.DEFAULT_ADMIN_ROLE(), deployer);
        strategy.renounceRole(strategy.PROCESSOR_MANAGER_ROLE(), deployer);
        strategy.renounceRole(strategy.BUFFER_MANAGER_ROLE(), deployer);
        strategy.renounceRole(strategy.PROVIDER_MANAGER_ROLE(), deployer);
        strategy.renounceRole(strategy.ASSET_MANAGER_ROLE(), deployer);
        strategy.renounceRole(strategy.UNPAUSER_ROLE(), deployer);
        strategy.renounceRole(strategy.ALLOCATOR_MANAGER_ROLE(), deployer);
        accountingToken.renounceRole(accountingToken.DEFAULT_ADMIN_ROLE(), deployer);
        accountingModule.renounceRole(accountingModule.DEFAULT_ADMIN_ROLE(), deployer);
    }

    function renounceTemporaryRolesStrategy(
        FlexStrategy strategy,
        AccountingModule accountingModule,
        AccountingToken accountingToken,
        address deployer
    )
        internal
    {
        renounceTemporaryRoles(strategy, accountingModule, accountingToken, deployer);
    }
}
