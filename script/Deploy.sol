// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {Vaulty} from "../src/Vaulty.sol";
import {VToken} from "../src/VToken.sol";

contract DeployScript is Script {
    Vaulty public protocol;
    VToken public underlyingAssset;

    function setUp() public {}

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);

        underlyingAssset = new VToken("VToken", "VLT", 1000000 * 10 ** 18);
        
        protocol = new Vaulty(underlyingAssset, "VToken", "VLT", msg.sender, 100e18);
        
        vm.stopBroadcast();
        
        console.log("Contract deployed at:", address(protocol));
    }

}

// source.env

// forge script script/Deploy.s.sol:DeployScript \--rpc-url $SEPOLIA_RPC_URL \--broadcast \--verify \--etherscan-api-key $ETHERSCAN_API_KEY \-vvvv

