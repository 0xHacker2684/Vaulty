
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title CustomVault
 * @dev Custom ERC4626 vault with deposit/withdraw fees and limits
 */
contract vaulty is ERC4626, Ownable, ReentrancyGuard {
    // State variables
    uint256 private depositFee; // Fee in basis points (100 = 1%)
    uint256 private withdrawFee; // Fee in basis points (100 = 1%)
    uint256 private maxDepositLimit; // Maximum deposit per transaction
    uint256 private minWithdrawAmount; // Minimum withdraw amount
    bool private depositsEnabled;
    bool private withdrawalsEnabled;
    
    address private feeRecipient;
    uint256 private totalFeesCollected;
    
    // Constants
    uint256 private constant BASIS_POINTS = 10000;
    uint256 private constant MAX_FEE = 1000; // 10% max fee
    
    // Events
    event DepositFeeUpdated(uint256 newFee);
    event WithdrawFeeUpdated(uint256 newFee);
    event MaxDepositLimitUpdated(uint256 newLimit);
    event MinWithdrawAmountUpdated(uint256 newAmount);
    event DepositsToggled(bool enabled);
    event WithdrawalsToggled(bool enabled);
    event FeeRecipientUpdated(address newRecipient);
    event FeesCollected(address recipient, uint256 amount);
    
    /**
     * @dev Constructor
     * @param asset_ The underlying ERC20 token
     * @param name_ Vault token name
     * @param symbol_ Vault token symbol
     */
    constructor(
        IERC20 asset_,
        string memory name_,
        string memory symbol_,
        address _feeRecipient
    ) ERC4626(asset_) ERC20(name_, symbol_) Ownable(msg.sender) {
        feeRecipient = _feeRecipient;
    }
    
    // ============ Overridden Deposit Functions ============
    
    /**
     * @dev Override deposit to add fees and limits
     */
    function deposit(uint256 assets, address receiver) 
        public 
        virtual 
        override 
        nonReentrant 
        returns (uint256) 
    {
        require(depositsEnabled, "Deposits are disabled");
        require(assets <= maxDepositLimit, "Exceeds max deposit limit");
        require(assets > 0, "Cannot deposit zero");
        
        // Calculate fee
        uint256 fee = (assets * depositFee) / BASIS_POINTS;
        uint256 assetsAfterFee = assets - fee;
        
        // Calculate shares based on assets after fee
        uint256 shares = previewDeposit(assetsAfterFee);
        require(shares > 0, "Zero shares");
        
        // Transfer total assets from sender
        SafeERC20.safeTransferFrom(IERC20(asset()), msg.sender, address(this), assets);
        
        // Track fees
        if (fee > 0) {
            totalFeesCollected += fee;
        }
        
        // Mint shares for assets after fee
        _mint(receiver, shares);
        
        emit Deposit(msg.sender, receiver, assets, shares);
        
        return shares;
    }
    
    /**
     * @dev Override mint to add fees
     */
    function mint(uint256 shares, address receiver) 
        public 
        virtual 
        override 
        nonReentrant 
        returns (uint256) 
    {
        require(depositsEnabled, "Deposits are disabled");
        require(shares > 0, "Cannot mint zero shares");
        
        // Calculate assets needed including fee
        uint256 assetsBeforeFee = previewMint(shares);
        uint256 fee = (assetsBeforeFee * depositFee) / (BASIS_POINTS - depositFee);
        uint256 totalAssets = assetsBeforeFee + fee;
        
        require(totalAssets <= maxDepositLimit, "Exceeds max deposit limit");
        
        // Transfer assets
        SafeERC20.safeTransferFrom(IERC20(asset()), msg.sender, address(this), totalAssets);
        
        // Track fees
        if (fee > 0) {
            totalFeesCollected += fee;
        }
        
        // Mint shares
        _mint(receiver, shares);
        
        emit Deposit(msg.sender, receiver, totalAssets, shares);
        
        return totalAssets;
    }
    
    // ============ Overridden Withdraw Functions ============
    
    /**
     * @dev Override withdraw to add fees and limits
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public virtual override nonReentrant returns (uint256) {
        require(withdrawalsEnabled, "Withdrawals are disabled");
        require(assets >= minWithdrawAmount, "Below minimum withdraw");
        require(assets > 0, "Cannot withdraw zero");
        
        // Calculate shares needed
        uint256 shares = previewWithdraw(assets);
        
        // Check and update allowance
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }
        
        // Calculate fee
        uint256 fee = (assets * withdrawFee) / BASIS_POINTS;
        uint256 assetsAfterFee = assets - fee;
        
        // Track fees
        if (fee > 0) {
            totalFeesCollected += fee;
        }
        
        // Burn shares and transfer assets
        _burn(owner, shares);
        SafeERC20.safeTransfer(IERC20(asset()), receiver, assetsAfterFee);
        
        emit Withdraw(msg.sender, receiver, owner, assets, shares);
        
        return shares;
    }
    
    /**
     * @dev Override redeem to add fees
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public virtual override nonReentrant returns (uint256) {
        require(withdrawalsEnabled, "Withdrawals are disabled");
        require(shares > 0, "Cannot redeem zero shares");
        
        // Check and update allowance
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }
        
        // Calculate assets
        uint256 assets = previewRedeem(shares);
        require(assets >= minWithdrawAmount, "Below minimum withdraw");
        
        // Calculate fee
        uint256 fee = (assets * withdrawFee) / BASIS_POINTS;
        uint256 assetsAfterFee = assets - fee;
        
        // Track fees
        if (fee > 0) {
            totalFeesCollected += fee;
        }
        
        // Burn shares and transfer assets
        _burn(owner, shares);
        SafeERC20.safeTransfer(IERC20(asset()), receiver, assetsAfterFee);
        
        emit Withdraw(msg.sender, receiver, owner, assets, shares);
        
        return assets;
    }
    
    // ============ Setter Functions ============
    
    /**
     * @dev Set deposit fee
     * @param newFee Fee in basis points
     */
    function setDepositFee(uint256 newFee) external onlyOwner {
        require(newFee <= MAX_FEE, "Fee too high");
        depositFee = newFee;
        emit DepositFeeUpdated(newFee);
    }
    
    /**
     * @dev Set withdraw fee
     * @param newFee Fee in basis points
     */
    function setWithdrawFee(uint256 newFee) external onlyOwner {
        require(newFee <= MAX_FEE, "Fee too high");
        withdrawFee = newFee;
        emit WithdrawFeeUpdated(newFee);
    }
    
    /**
     * @dev Set maximum deposit limit
     * @param newLimit New maximum deposit amount
     */
    function setMaxDepositLimit(uint256 newLimit) external onlyOwner {
        maxDepositLimit = newLimit;
        emit MaxDepositLimitUpdated(newLimit);
    }
    
    /**
     * @dev Set minimum withdraw amount
     * @param newAmount New minimum withdraw amount
     */
    function setMinWithdrawAmount(uint256 newAmount) external onlyOwner {
        minWithdrawAmount = newAmount;
        emit MinWithdrawAmountUpdated(newAmount);
    }
    
    /**
     * @dev Enable or disable deposits
     * @param enabled True to enable, false to disable
     */
    function setDepositsEnabled(bool enabled) external onlyOwner {
        depositsEnabled = enabled;
        emit DepositsToggled(enabled);
    }
    
    /**
     * @dev Enable or disable withdrawals
     * @param enabled True to enable, false to disable
     */
    function setWithdrawalsEnabled(bool enabled) external onlyOwner {
        withdrawalsEnabled = enabled;
        emit WithdrawalsToggled(enabled);
    }
    
    /**
     * @dev Set fee recipient address
     * @param newRecipient Address to receive fees
     */
    function setFeeRecipient(address newRecipient) external onlyOwner {
        require(newRecipient != address(0), "Invalid recipient");
        feeRecipient = newRecipient;
        emit FeeRecipientUpdated(newRecipient);
    }
    
    /**
     * @dev Collect accumulated fees
     */
    function collectFees() external onlyOwner {
        require(totalFeesCollected > 0, "No fees to collect");
        uint256 amount = totalFeesCollected;
        totalFeesCollected = 0;
        SafeERC20.safeTransfer(IERC20(asset()), feeRecipient, amount);
        emit FeesCollected(feeRecipient, amount);
    }
    
    // ============ Getter Functions ============
    
    /**
     * @dev Get deposit fee
     * @return Current deposit fee in basis points
     */
    function getDepositFee() external view returns (uint256) {
        return depositFee;
    }
    
    /**
     * @dev Get withdraw fee
     * @return Current withdraw fee in basis points
     */
    function getWithdrawFee() external view returns (uint256) {
        return withdrawFee;
    }
    
    /**
     * @dev Get maximum deposit limit
     * @return Current maximum deposit limit
     */
    function getMaxDepositLimit() external view returns (uint256) {
        return maxDepositLimit;
    }
    
    /**
     * @dev Get minimum withdraw amount
     * @return Current minimum withdraw amount
     */
    function getMinWithdrawAmount() external view returns (uint256) {
        return minWithdrawAmount;
    }
    
    /**
     * @dev Check if deposits are enabled
     * @return True if deposits are enabled
     */
    function areDepositsEnabled() external view returns (bool) {
        return depositsEnabled;
    }
    
    /**
     * @dev Check if withdrawals are enabled
     * @return True if withdrawals are enabled
     */
    function areWithdrawalsEnabled() external view returns (bool) {
        return withdrawalsEnabled;
    }
    
    /**
     * @dev Get fee recipient address
     * @return Address of fee recipient
     */
    function getFeeRecipient() external view returns (address) {
        return feeRecipient;
    }
    
    /**
     * @dev Get total fees collected
     * @return Total fees collected and not yet withdrawn
     */
    function getTotalFeesCollected() external view returns (uint256) {
        return totalFeesCollected;
    }
    
    /**
     * @dev Get vault information
     * @return Struct containing all vault parameters
     */
    function getVaultInfo() external view returns (
        uint256 _depositFee,
        uint256 _withdrawFee,
        uint256 _maxDepositLimit,
        uint256 _minWithdrawAmount,
        bool _depositsEnabled,
        bool _withdrawalsEnabled,
        address _feeRecipient,
        uint256 _totalFeesCollected
    ) {
        return (
            depositFee,
            withdrawFee,
            maxDepositLimit,
            minWithdrawAmount,
            depositsEnabled,
            withdrawalsEnabled,
            feeRecipient,
            totalFeesCollected
        );
    }
}