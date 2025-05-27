// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

contract MockAccountingModule {
    address public accountingToken;

    function setAccountingToken(address _accountingToken) public {
        accountingToken = _accountingToken;
    }
}
