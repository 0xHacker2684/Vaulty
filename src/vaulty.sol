
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title Vaulty
 * @dev Custom ERC4626 vault with deposit/withdraw fees and limits
 */
contract Vaulty is ERC4626, Ownable, ReentrancyGuard {

    uint256 private depositFee;
    uint256 private withdrawFee;
    uint256 private maxDepositLimit;
    uint256 private minWithdrawAmount;
    bool private depositsEnabled;
    bool private withdrawalsEnabled;
    
    address private feeRecipient;
    uint256 private totalFeesCollected;
    
    uint256 private constant BASIS_POINTS = 10000;
    uint256 private constant MAX_FEE = 1000;
    
    event DepositFeeUpdated(uint256 newFee);
    event WithdrawFeeUpdated(uint256 newFee);
    event MaxDepositLimitUpdated(uint256 newLimit);
    event MinWithdrawAmountUpdated(uint256 newAmount);
    event DepositsToggled(bool enabled);
    event WithdrawalsToggled(bool enabled);
    event FeeRecipientUpdated(address newRecipient);
    event FeesCollected(address recipient, uint256 amount);
    

    constructor(
        IERC20 asset_,
        string memory name_,
        string memory symbol_,
        address _feeRecipient,
        uint256 _maxDepositLimit
    ) ERC4626(asset_) ERC20(name_, symbol_) Ownable(msg.sender) {
        feeRecipient = _feeRecipient;
        maxDepositLimit = _maxDepositLimit;
    }
    
    
    function deposit(uint256 assets, address receiver) 
        public 
        virtual 
        override 
        nonReentrant 
        returns (uint256) 
    {
        require(assets > 0, "Cannot deposit zero");
        require(assets <= maxDepositLimit, "Exceeds max deposit limit");

        uint256 shares = previewDeposit(assets);
        require(shares > 0, "Zero shares");

        SafeERC20.safeTransferFrom(IERC20(asset()), msg.sender, address(this), assets);
        
        _mint(receiver, shares);
        
        emit Deposit(msg.sender, receiver, assets, shares);
        
        return shares;
    }
    
    
    function mint(uint256 shares, address receiver) 
        public 
        virtual 
        override 
        nonReentrant 
        returns (uint256) 
    {
        require(shares > 0, "Cannot mint zero shares");
        
        uint256 assets = previewMint(shares);
        require(assets > 0, "Zero assets");
        
        require(assets <= maxDepositLimit, "Exceeds max deposit limit");
        
        SafeERC20.safeTransferFrom(IERC20(asset()), msg.sender, address(this), assets);
        
        _mint(receiver, shares);
        
        emit Deposit(msg.sender, receiver, assets, shares);
        
        return shares;
    }
    
   
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public virtual override nonReentrant returns (uint256) {
        require(assets > 0, "Cannot withdraw zero");
        
        uint256 shares = previewWithdraw(assets);
        
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }
        
        _burn(owner, shares);
        SafeERC20.safeTransfer(IERC20(asset()), receiver, assets);
        
        emit Withdraw(msg.sender, receiver, owner, assets, shares);
        
        return shares;
    }
    
    
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public virtual override nonReentrant returns (uint256) {
        require(shares > 0, "Cannot redeem zero shares");
        
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }
        
        uint256 assets = previewRedeem(shares);
        require(assets >= minWithdrawAmount, "Below minimum withdraw");
        
        _burn(owner, shares);

        SafeERC20.safeTransfer(IERC20(asset()), receiver, assets);
        
        emit Withdraw(msg.sender, receiver, owner, assets, shares);
        
        return assets;
    }
    


    function setDepositFee(uint256 newFee) external onlyOwner {
        require(newFee <= MAX_FEE, "Fee too high");
        depositFee = newFee;
        emit DepositFeeUpdated(newFee);
    }
    
   
    function setWithdrawFee(uint256 newFee) external onlyOwner {
        require(newFee <= MAX_FEE, "Fee too high");
        withdrawFee = newFee;
        emit WithdrawFeeUpdated(newFee);
    }
    
   
    function setMaxDepositLimit(uint256 newLimit) external onlyOwner {
        maxDepositLimit = newLimit;
        emit MaxDepositLimitUpdated(newLimit);
    }
    
   
    function setMinWithdrawAmount(uint256 newAmount) external onlyOwner {
        minWithdrawAmount = newAmount;
        emit MinWithdrawAmountUpdated(newAmount);
    }
    
   

    function setDepositsEnabled(bool enabled) external onlyOwner {
        depositsEnabled = enabled;
        emit DepositsToggled(enabled);
    }
    
    
    function setWithdrawalsEnabled(bool enabled) external onlyOwner {
        withdrawalsEnabled = enabled;
        emit WithdrawalsToggled(enabled);
    }
    
   
    function setFeeRecipient(address newRecipient) external onlyOwner {
        require(newRecipient != address(0), "Invalid recipient");
        feeRecipient = newRecipient;
        emit FeeRecipientUpdated(newRecipient);
    }
    
   
    function collectFees() external onlyOwner {
        require(totalFeesCollected > 0, "No fees to collect");
        uint256 amount = totalFeesCollected;
        totalFeesCollected = 0;
        SafeERC20.safeTransfer(IERC20(asset()), feeRecipient, amount);
        emit FeesCollected(feeRecipient, amount);
    }
    
   
    function getDepositFee() external view returns (uint256) {
        return depositFee;
    }
    
    
    function getWithdrawFee() external view returns (uint256) {
        return withdrawFee;
    }
    
    
    function getMaxDepositLimit() external view returns (uint256) {
        return maxDepositLimit;
    }
    
    
    function getMinWithdrawAmount() external view returns (uint256) {
        return minWithdrawAmount;
    }
    
    
    function areDepositsEnabled() external view returns (bool) {
        return depositsEnabled;
    }
    
    
    function areWithdrawalsEnabled() external view returns (bool) {
        return withdrawalsEnabled;
    }
    
   
    function getFeeRecipient() external view returns (address) {
        return feeRecipient;
    }
    
  
    function getTotalFeesCollected() external view returns (uint256) {
        return totalFeesCollected;
    }
    
}