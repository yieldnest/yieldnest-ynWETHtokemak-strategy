// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import { IAccountingModule } from "@yieldnest-flex-strategy/AccountingModule.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IFlexStrategy } from "@yieldnest-flex-strategy/FlexStrategy.sol";

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

    function withdraw(uint256 amount, address recipient) public {
        am.withdraw(amount, recipient);
        IERC20(am.BASE_ASSET()).transfer(recipient, amount);
    }

    function decimals() public pure returns (uint8) {
        return 18;
    }

    function convertToAssets(uint256 amount) public pure returns (uint256) {
        return amount;
    }

    function convertToShares(uint256 amount) public pure returns (uint256) {
        return amount;
    }

    function processAccounting() public { }
}
