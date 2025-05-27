// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import { Test, console } from "forge-std/Test.sol";
import { DeployFlexStrategy } from "script/DeployFlexStrategy.s.sol";
import { VerifyFlexStrategy } from "script/verification/VerifyFlexStrategy.s.sol";
import { FlexStrategy } from "src/FlexStrategy.sol";
import { AccountingModule } from "src/AccountingModule.sol";
import { AccountingToken } from "src/AccountingToken.sol";
import { IVault } from "@yieldnest-vault/interface/IVault.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { BaseScript } from "script/BaseScript.sol";
import { UpgradeUtils } from "script/UpgradeUtils.sol";
import { MainnetActors } from "@yieldnest-vault-script/Actors.sol";
import { ProxyUtils } from "@yieldnest-vault-script/ProxyUtils.sol";
import { RolesVerification } from "script/verification/RolesVerification.sol";

contract FlexStrategyDeployment is Test {
    DeployFlexStrategy public deployment;
    address DEPLOYER = address(0xd34db33f);

    function setUp() public {
        deployment = new DeployFlexStrategy();
        deployment.setEnv(BaseScript.Env.TEST);
        deployment.run();
    }

    function test_verify_setup() public {
        VerifyFlexStrategy verify = new VerifyFlexStrategy();
        verify.setEnv(BaseScript.Env.TEST);
        verify.run();
    }

    function test_upgrade_success() public {
        FlexStrategy newImpl = new FlexStrategy();
        address securityCouncil = MainnetActors(address(deployment.actors())).YnSecurityCouncil();
        UpgradeUtils.timelockUpgrade(
            deployment.timelock(), securityCouncil, address(deployment.strategy()), address(newImpl)
        );

        assertEq(address(ProxyUtils.getImplementation(address(deployment.strategy()))), address(newImpl));
    }

    function test_addNewAdmin_success() public {
        address newAdmin = address(0x1234567890123456789012345678901234567890);

        vm.startPrank(deployment.actors().ADMIN());
        deployment.strategy().grantRole(deployment.strategy().DEFAULT_ADMIN_ROLE(), newAdmin);
        RolesVerification.verifyRole(
            deployment.strategy(),
            newAdmin,
            deployment.strategy().DEFAULT_ADMIN_ROLE(),
            true,
            "newAdmin has DEFAULT_ADMIN_ROLE"
        );
    }
}
