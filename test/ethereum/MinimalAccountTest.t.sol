// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {MinimalAccount} from "src/ethereum/MinimalAccount.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {DeployMinimal} from "script/DeployMinimal.s.sol";
import {SendPackedUserOp, PackedUserOperation, IEntryPoint, MessageHashUtils} from "script/SendPackedUserOp.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract MinimalAccountTest is Test {
    using MessageHashUtils for bytes32;

    HelperConfig helperConfig;
    MinimalAccount minimalAccount;
    ERC20Mock usdc;
    SendPackedUserOp sendPackedUserOp;

    uint256 constant USDC_AMOUNT = 1e18;

    address randomUser = makeAddr("randomUser");

    function setUp() public {
        DeployMinimal deployMin = new DeployMinimal();
        (helperConfig, minimalAccount) = deployMin.deployMinimalAccount();
        usdc = new ERC20Mock();
        sendPackedUserOp = new SendPackedUserOp();
    }

    function testOwnerCanExecuteCommands() public {
        // Arrange
        assertEq(usdc.balanceOf(address(minimalAccount)), 0);
        address dest = address(usdc);
        uint256 value = 0;
        bytes memory functionData =
            abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccount), USDC_AMOUNT);
        // Act
        vm.prank(minimalAccount.owner());
        minimalAccount.execute(dest, value, functionData);
        // Assert
        assertEq(usdc.balanceOf(address(minimalAccount)), USDC_AMOUNT);
    }

    function testNonOwnerCannotExecuteCommands() public {
        // Arrange
        assertEq(usdc.balanceOf(address(minimalAccount)), 0);
        address dest = address(usdc);
        uint256 value = 0;
        bytes memory functionData =
            abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccount), USDC_AMOUNT);
        // Act
        vm.prank(randomUser);
        vm.expectRevert(MinimalAccount.MinimalAccount__OnlyCallableByEntryPointOrOwner.selector);
        minimalAccount.execute(dest, value, functionData);
        // Assert
        assertEq(usdc.balanceOf(address(minimalAccount)), 0);
    }

    function testRecoverOnSignedUserOp() public {
        // Arrange
/*         address[] memory wallets = vm.getWallets();
        address wallet1 = wallets[1];
        console.log("wallet", address(wallet1)); */

        address dest = address(usdc);
        uint256 value = 0;
        bytes memory functionData =
            abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccount), USDC_AMOUNT);
        bytes memory executeCallData =
            abi.encodeWithSelector(minimalAccount.execute.selector, dest, value, functionData);
        PackedUserOperation memory userOp =
            sendPackedUserOp.generateSignedUserOperation(executeCallData, helperConfig.getConfig(),address(minimalAccount));
        bytes32 userOpHash = IEntryPoint(helperConfig.getConfig().entryPoint).getUserOpHash(userOp);
        // Act
        address actualSigner = ECDSA.recover(userOpHash.toEthSignedMessageHash(), userOp.signature);
        // Assert
        assertEq(actualSigner, minimalAccount.owner());
    }
        function testValidationOfUserOps() public {
            // 1. Sign UserOps
            // 2. Call validateUserOp
            // 3. Assert return is correct
        // Arrange 
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        address dest = address(usdc);
        uint256 value = 0;
        uint256 missingFunds = 1e18;
        bytes memory functionData =
            abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccount), USDC_AMOUNT);
        bytes memory executeCallData =
            abi.encodeWithSelector(minimalAccount.execute.selector, dest, value, functionData);
        PackedUserOperation memory userOp =
            sendPackedUserOp.generateSignedUserOperation(executeCallData, config, address(minimalAccount));
        bytes32 userOpHash = IEntryPoint(config.entryPoint).getUserOpHash(userOp);
        // Act
        vm.prank(address(config.entryPoint));
        uint256 validationData = minimalAccount.validateUserOp(userOp, userOpHash, missingFunds);
        // Assert
        assertEq(validationData, 0);
    }

    // Final test
    function testEntryPointCanExecuteCommands() public {
        // Arrange 
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        address dest = address(usdc);
        uint256 value = 0;
        bytes memory functionData =
            abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccount), USDC_AMOUNT);
        bytes memory executeCallData =
            abi.encodeWithSelector(minimalAccount.execute.selector, dest, value, functionData);
        PackedUserOperation memory userOp =
            sendPackedUserOp.generateSignedUserOperation(executeCallData, config, address(minimalAccount));
            
        vm.deal(address(minimalAccount),1e18);
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0]= userOp; 
        // Act
        vm.prank(randomUser);
        IEntryPoint(config.entryPoint).handleOps(ops, payable(randomUser));

        // Assert
        assertEq(usdc.balanceOf(address(minimalAccount)), USDC_AMOUNT);
    }
}
