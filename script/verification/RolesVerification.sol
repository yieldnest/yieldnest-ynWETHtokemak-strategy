// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.28;

import { console } from "forge-std/console.sol";
import { Vm } from "forge-std/Vm.sol";
import { IAccessControl } from "openzeppelin-contracts/contracts/access/IAccessControl.sol";
import { TimelockController } from "openzeppelin-contracts/contracts/governance/TimelockController.sol";
import { IActors } from "@yieldnest-vault-script/Actors.sol";
import { FlexStrategy } from "src/FlexStrategy.sol";
import { AccountingModule } from "src/AccountingModule.sol";
import { AccountingToken } from "src/AccountingToken.sol";

library RolesVerification {
    function verifyRole(
        IAccessControl control,
        address account,
        bytes32 role,
        bool expected,
        string memory message
    )
        internal
        view
    {
        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

        bool hasRole = control.hasRole(role, account);
        console.log(hasRole == expected ? "\u2705" : "\u274C", message, account);
        vm.assertEq(hasRole, expected, message);
    }

    function verifyDefaultRoles(
        FlexStrategy strategy,
        AccountingModule accountingModule,
        AccountingToken accountingToken,
        TimelockController timelock,
        IActors actors
    )
        internal
        view
    {
        verifyRole(strategy, actors.ADMIN(), strategy.DEFAULT_ADMIN_ROLE(), true, "Admin has DEFAULT_ADMIN_ROLE");
        verifyRole(strategy, actors.PROCESSOR(), strategy.PROCESSOR_ROLE(), true, "Processor has PROCESSOR_ROLE");
        verifyRole(strategy, actors.PAUSER(), strategy.PAUSER_ROLE(), true, "Pauser has PAUSER_ROLE");
        verifyRole(strategy, actors.UNPAUSER(), strategy.UNPAUSER_ROLE(), true, "Unpauser has UNPAUSER_ROLE");

        verifyRole(
            strategy, address(timelock), strategy.PROVIDER_MANAGER_ROLE(), true, "Timelock has PROVIDER_MANAGER_ROLE"
        );
        verifyRole(strategy, address(timelock), strategy.ASSET_MANAGER_ROLE(), true, "Timelock has ASSET_MANAGER_ROLE");
        verifyRole(
            strategy, address(timelock), strategy.BUFFER_MANAGER_ROLE(), true, "Timelock has BUFFER_MANAGER_ROLE"
        );
        verifyRole(
            strategy, address(timelock), strategy.PROCESSOR_MANAGER_ROLE(), true, "Timelock has PROCESSOR_MANAGER_ROLE"
        );
        verifyRole(
            strategy, address(timelock), strategy.ALLOCATOR_MANAGER_ROLE(), true, "Timelock has ALLOCATOR_MANAGER_ROLE"
        );
        verifyRole(
            accountingModule,
            address(timelock),
            accountingModule.SAFE_MANAGER_ROLE(),
            true,
            "Timelock has accountingModule.SAFE_MANAGER_ROLE"
        );
        verifyRole(
            accountingModule,
            address(timelock),
            accountingModule.DEFAULT_ADMIN_ROLE(),
            true,
            "Timelock has accountingModule.DEFAULT_ADMIN_ROLE"
        );
        verifyRole(
            accountingToken,
            address(timelock),
            accountingToken.DEFAULT_ADMIN_ROLE(),
            true,
            "Timelock has accountingToken.DEFAULT_ADMIN_ROLE"
        );
    }

    function verifyTemporaryRoles(
        FlexStrategy strategy,
        AccountingModule accountingModule,
        AccountingToken accountingToken,
        address deployer
    )
        internal
        view
    {
        verifyRole(strategy, deployer, strategy.DEFAULT_ADMIN_ROLE(), false, "Deployer has DEFAULT_ADMIN_ROLE");
        verifyRole(strategy, deployer, strategy.PROCESSOR_MANAGER_ROLE(), false, "Deployer has PROCESSOR_MANAGER_ROLE");
        verifyRole(strategy, deployer, strategy.BUFFER_MANAGER_ROLE(), false, "Deployer has BUFFER_MANAGER_ROLE");
        verifyRole(strategy, deployer, strategy.PROVIDER_MANAGER_ROLE(), false, "Deployer has PROVIDER_MANAGER_ROLE");
        verifyRole(strategy, deployer, strategy.ASSET_MANAGER_ROLE(), false, "Deployer has ASSET_MANAGER_ROLE");
        verifyRole(strategy, deployer, strategy.UNPAUSER_ROLE(), false, "Deployer has UNPAUSER_ROLE");
        verifyRole(
            accountingModule,
            deployer,
            accountingModule.DEFAULT_ADMIN_ROLE(),
            false,
            "Deployer has accountingModule.DEFAULT_ADMIN_ROLE"
        );
        verifyRole(
            accountingToken,
            deployer,
            accountingToken.DEFAULT_ADMIN_ROLE(),
            false,
            "Deployer has accountingToken.DEFAULT_ADMIN_ROLE"
        );
    }
}
