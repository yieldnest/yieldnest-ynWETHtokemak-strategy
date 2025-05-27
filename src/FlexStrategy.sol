// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import { BaseStrategy } from "@yieldnest-vault/strategy/BaseStrategy.sol";
import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IAccountingModule } from "./AccountingModule.sol";

interface IFlexStrategy {
    error OnlyBaseAsset();
    error NoAccountingModule();
    error InvariantViolation();

    event AccountingModuleUpdated(address newValue, address oldValue);
}

/**
 * Flex strategy that proxies the deposited base asset to an associated safe,
 * minting IOU accounting tokens in the process to represent transferred assets.
 */
contract FlexStrategy is IFlexStrategy, BaseStrategy {
    using SafeERC20 for IERC20;

    IAccountingModule public accountingModule;

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the vault.
     * @param admin The address of the admin.
     * @param name The name of the vault.
     * @param symbol The symbol of the vault.
     * @param decimals_ The number of decimals for the vault token.
     * @param baseAsset The base asset of the vault.
     * @param paused_ Whether the vault should start in a paused state.
     */
    function initialize(
        address admin,
        string memory name,
        string memory symbol,
        uint8 decimals_,
        address baseAsset,
        bool paused_
    )
        external
        virtual
        initializer
    {
        _initialize(
            admin,
            name,
            symbol,
            decimals_,
            paused_,
            false, // countNativeAsset. MUST be false. accounting is done virtually.
            false, // alwaysComputeTotalAssets. MUST be false. accounting is done virtually.
            0 // defaultAssetIndex. MUST be 0. baseAsset is default
        );
        _addAsset(baseAsset, IERC20Metadata(baseAsset).decimals(), true);
        _setAssetWithdrawable(baseAsset, true);
    }

    modifier hasAccountingModule() {
        if (address(accountingModule) == address(0)) revert NoAccountingModule();
        _;
    }

    modifier checkInvariantAfter() {
        _;
        if (totalAssets() != IERC20(accountingModule.accountingToken()).balanceOf(address(this))) {
            revert InvariantViolation();
        }
    }

    /**
     * @notice Internal function to handle deposits.
     * @param asset_ The address of the asset.
     * @param caller The address of the caller.
     * @param receiver The address of the receiver.
     * @param assets The amount of assets to deposit.
     * @param shares The amount of shares to mint.
     * @param baseAssets The base asset conversion of shares.
     */
    function _deposit(
        address asset_,
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares,
        uint256 baseAssets
    )
        internal
        virtual
        override
        hasAccountingModule
        checkInvariantAfter
    {
        // call the base strategy deposit function for accounting
        super._deposit(asset_, caller, receiver, assets, shares, baseAssets);

        // virtual accounting
        accountingModule.deposit(assets);
    }

    /**
     * @notice Internal function to handle withdrawals for base asset
     * @param asset_ The address of the asset.
     * @param caller The address of the caller.
     * @param receiver The address of the receiver.
     * @param owner The address of the owner.
     * @param assets The amount of assets to withdraw.
     * @param shares The equivalent amount of shares.
     */
    function _withdrawAsset(
        address asset_,
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    )
        internal
        virtual
        override
        checkInvariantAfter
    {
        // check if the asset is withdrawable
        if (!_getBaseStrategyStorage().isAssetWithdrawable[asset_]) {
            revert AssetNotWithdrawable();
        }

        // call the base strategy withdraw function for accounting
        _subTotalAssets(_convertAssetToBase(asset_, assets));

        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        // NOTE: burn shares before withdrawing the assets
        _burn(owner, shares);

        // burn virtual tokens
        accountingModule.withdraw(assets);
        emit WithdrawAsset(caller, receiver, owner, asset_, assets, shares);
    }

    /**
     * @notice Sets the accounting module.
     * @param accountingModule_ address to check.
     * @dev Will revoke approvals for outgoing accounting module, and approve max for incoming accounting module.
     */
    function setAccountingModule(address accountingModule_) external virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        if (accountingModule_ == address(0)) revert ZeroAddress();
        emit AccountingModuleUpdated(accountingModule_, address(accountingModule));

        IAccountingModule oldAccounting = accountingModule;

        if (address(oldAccounting) != address(0)) {
            IERC20(asset()).approve(address(oldAccounting), 0);
        }

        accountingModule = IAccountingModule(accountingModule_);
        IERC20(asset()).approve(accountingModule_, type(uint256).max);
    }

    /**
     * @notice Processes the accounting of the vault by calculating the total base balance.
     * @dev This function iterates through the list of assets, gets their balances and rates,
     *      and updates the total assets denominated in the base asset.
     */
    function processAccounting() public virtual override nonReentrant checkInvariantAfter {
        _processAccounting();
    }

    /**
     * @notice Internal function to get the available amount of assets.
     * @param asset_ The address of the asset.
     * @return availableAssets The available amount of assets.
     * @dev Overriden. This function is used to calculate the available assets for a given asset,
     *      It returns the balance of the asset in the associated SAFE.
     */
    function _availableAssets(address asset_) internal view virtual override returns (uint256 availableAssets) {
        availableAssets = IERC20(asset_).balanceOf(accountingModule.safe());
    }

    /**
     * @notice Returns the fee on total amount.
     * @return 0 as this strategy does not charge any fee on total amount.
     */
    function _feeOnTotal(uint256) public view virtual override returns (uint256) {
        return 0;
    }

    /**
     * @notice Returns the fee on total amount.
     * @return 0 as this strategy does not charge any fee on total amount.
     */
    function _feeOnRaw(uint256) public view virtual override returns (uint256) {
        return 0;
    }

    /**
     * @notice Sets whether the vault should always compute total assets.
     * @dev Overridden. MUST always be false for flex strategy, because accounting is done virtually
     */
    function setAlwaysComputeTotalAssets(bool) external virtual override onlyRole(ASSET_MANAGER_ROLE) {
        revert InvariantViolation();
    }

    /**
     * @notice Computes the total assets in the vault.
     * @return totalBaseBalance The total assets in the vault.
     * @dev Overriden to compute total Accounting Tokens in vault.
     */
    function computeTotalAssets() public view virtual override returns (uint256 totalBaseBalance) {
        totalBaseBalance = IERC20(accountingModule.accountingToken()).balanceOf(address(this));
    }
}
