// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IProvider } from "@yieldnest-vault/interface/IProvider.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";

/**
 * Fixed rate provider that assumes 1:1 rate of added asset.
 */
contract FixedRateProvider is IProvider {
    address public immutable ASSET;
    uint8 public immutable DECIMALS;

    constructor(address asset) {
        ASSET = asset;
        DECIMALS = IERC20Metadata(asset).decimals();
    }

    error UnsupportedAsset(address asset);

    function getRate(address asset) external view returns (uint256 rate) {
        if (asset == ASSET) {
            return 10 ** DECIMALS;
        }

        revert UnsupportedAsset(asset);
    }
}
