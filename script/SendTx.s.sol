// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;
import "forge-std/Script.sol";


interface IVault{
    function deposit(uint256 amount, address receiver) external;
    function withdraw(uint256 shares, address receiver, address owner) external;
}

interface IVToken{
    function approve(address spender, uint256 amount) external returns (bool);  
    function mint(address to, uint256 amount) external;
}

contract SendTxScript is Script {
    function run() external {
        address Vault = 0x841ECE2d146eaD8724444e2BDA9594D4Ac0398Cc;
        address VToken = 0x841ECE2d146eaD8724444e2BDA9594D4Ac0398Cc;

        uint256 pk = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(pk);

        IVToken(VToken).mint(msg.sender, 100e18);
        IVToken(VToken).approve(Vault, 100e18);
        IVault(Vault).deposit(100e18, msg.sender);

        vm.stopBroadcast();
    }
}