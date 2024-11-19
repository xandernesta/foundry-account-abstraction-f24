// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {EntryPoint} from "lib/account-abstraction/contracts/core/EntryPoint.sol";

contract HelperConfig is Script {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error HelperConfig__InvalidChainId();

    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/
    struct NetworkConfig {
        address entryPoint;
        address account;
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    uint256 constant ETH_SEPOLIA_CHAIN_ID = 11155111;
    uint256 constant ZKSYNC_SEPOLIA_CHAIN_ID = 300;
    uint256 constant LOCAL_CHAIN_ID = 31337;
    address constant BURNER_WALLET = 0x5D09525B883020C65A2B5cd017FFbE51B6B6c58F;
    address constant ANVIL_DEFAULT_ACCOUNT = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    NetworkConfig public activeNetworkConfig;
    mapping(uint256 chainId => NetworkConfig) public s_networkConfigs;

    /*//////////////////////////////////////////////////////////////
                            FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    constructor(){
        s_networkConfigs[ETH_SEPOLIA_CHAIN_ID] = getSepoliaEthConfig();
        s_networkConfigs[ZKSYNC_SEPOLIA_CHAIN_ID] = getSepoliaZksyncConfig();
    }
    function getConfig() public returns(NetworkConfig memory){
        return getConfigByChainId(block.chainid);
    }
    function getConfigByChainId(uint256 chainId) public returns(NetworkConfig memory){
        if(chainId == LOCAL_CHAIN_ID){
            return getOrCreateAnvilConfig();
        } else if(s_networkConfigs[chainId].account != address(0)){
            return s_networkConfigs[chainId];
        } else {
         revert HelperConfig__InvalidChainId();
        }
    }
    function getSepoliaEthConfig() public pure returns(NetworkConfig memory){
        return NetworkConfig({
            entryPoint: 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789,
            account: BURNER_WALLET
        });
    }
    function getSepoliaZksyncConfig() public pure returns(NetworkConfig memory){
        return NetworkConfig({
            entryPoint: address(0), // There is no entrypoint in zkSync!
            account: BURNER_WALLET
        });
    }
    function getOrCreateAnvilConfig() public returns(NetworkConfig memory){
        if(activeNetworkConfig.account != address(0)){
            return activeNetworkConfig;
        }
        // else deploy a mock entryPoint contract
        console2.log("Deploying mocks...");
        vm.startBroadcast(ANVIL_DEFAULT_ACCOUNT);
        EntryPoint entryPointMock = new EntryPoint();
        // ERC20Mock erc20Mock = new ERC20Mock();
        vm.stopBroadcast();
        console2.log("Mocks deployed!");
        activeNetworkConfig = NetworkConfig({
            entryPoint: address(entryPointMock),
            account: ANVIL_DEFAULT_ACCOUNT
        });
        return activeNetworkConfig;
    }
}