// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {MinimalAccount} from "src/ethereum/MinimalAccount.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";

contract DeployMinimal is Script {

    function run() public {
        deployMinimalAccount();
    }

    function deployMinimalAccount() public returns(HelperConfig, MinimalAccount){
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        vm.startBroadcast(config.account);
            MinimalAccount minAA = new MinimalAccount(address(config.entryPoint));
            minAA.transferOwnership(config.account);
        vm.stopBroadcast();

        return (helperConfig, minAA);
    }
}