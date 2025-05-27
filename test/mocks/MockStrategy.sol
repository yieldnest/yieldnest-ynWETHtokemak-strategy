// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import { IAccountingModule } from "../../src/AccountingModule.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IFlexStrategy } from "../../src/FlexStrategy.sol";

contract MockStrategy is IFlexStrategy {
    IAccountingModule am;

    function setAccountingModule(IAccountingModule am_) public {
        am = am_;
        IERC20(am.BASE_ASSET()).approve(address(am), type(uint256).max);
        IERC20(am.accountingToken()).approve(address(am), type(uint256).max);
    }

    function deposit(uint256 amount) public {
        IERC20(am.BASE_ASSET()).transferFrom(msg.sender, address(this), amount);
        am.deposit(amount);
    }

    function withdraw(uint256 amount) public {
        am.withdraw(amount);
        IERC20(am.BASE_ASSET()).transfer(msg.sender, amount);
    }

    function processAccounting() public { }
}
