// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import {Provider} from "lib/yieldnest-vault/src/module/Provider.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";

contract YnETHxMockProvider is Provider {
    address public immutable FLEX_STRATEGY;
    uint8 public immutable DECIMALS;

    constructor(address flexStrategy) {
        FLEX_STRATEGY = flexStrategy;
        DECIMALS = IERC20Metadata(flexStrategy).decimals();
    }

    function getRate(address asset) public view virtual override returns (uint256 rate) {
        if (asset == FLEX_STRATEGY) {
            return 10 ** DECIMALS;
        } else {
            return super.getRate(asset);
        }
    }
}