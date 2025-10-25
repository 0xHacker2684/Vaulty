// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import "forge-std/Test.sol";
import {Vaulty} from "../src/Vaulty.sol";
import {VToken} from "../src/VToken.sol";

contract VaultTest is Test{

    address recipient = makeAddr("feeRecipient");
    address bob = makeAddr("bob");  
    address alice = makeAddr("alice");

    Vaulty public vaulty;
    VToken public vToken;

    function setUp() public{
        vToken = new VToken("VToken", "VTK", 100000e18);
        vaulty = new Vaulty(vToken, "VToken", "VTK",recipient, 1000e18);

        vToken.mint(alice, 1000e18);
        vToken.mint(bob, 1000e18);
    }

    function testFirstDeposit() public {

        vm.startPrank(bob);
        vToken.approve(address(vaulty), 1);
        vaulty.deposit(1, bob);  
        vToken.transfer(address(vaulty), 100e18);
        vm.stopPrank();


        vm.startPrank(alice);
        vToken.approve(address(vaulty), 100e18);
        vaulty.deposit(100e18, alice);  
        vm.stopPrank(); 

        vaulty.balanceOf(alice);
        vaulty.balanceOf(bob);  

        vm.startPrank(bob);
        vaulty.withdraw(1, bob, bob);
        vm.stopPrank();

        vm.startPrank(alice);
        vaulty.withdraw(1, alice, alice);
        vm.stopPrank();


    }
}
