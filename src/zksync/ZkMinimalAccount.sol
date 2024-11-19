// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// zkSync Era Imports 
import {IAccount, ACCOUNT_VALIDATION_SUCCESS_MAGIC} from "lib/foundry-era-contracts/src/system-contracts/contracts/interfaces/IAccount.sol";
import {Transaction, MemoryTransactionHelper} from "lib/foundry-era-contracts/src/system-contracts/contracts/libraries/MemoryTransactionHelper.sol";
import {SystemContractsCaller} from "lib/foundry-era-contracts/src/system-contracts/contracts/libraries/SystemContractsCaller.sol";
import {NONCE_HOLDER_SYSTEM_CONTRACT, BOOTLOADER_FORMAL_ADDRESS, DEPLOYER_SYSTEM_CONTRACT} from "lib/foundry-era-contracts/src/system-contracts/contracts/Constants.sol";
import {INonceHolder} from "lib/foundry-era-contracts/src/system-contracts/contracts/interfaces/INonceHolder.sol";
import {Utils} from "lib/foundry-era-contracts/src/system-contracts/contracts/libraries/Utils.sol";

// OZ Imports
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * TxType 113 (0x71) Lifecycle - Account Abstraction Txn phases
 * msg.sender will be the bootloader system contract
 * 
 * Phase 1 - Validation
 * 1. User sends their txn to the "zkSync API Client" (a sort of "light node")
 * 2. zkSync API Client checks to see if the nonce is unique by querying the NonceHolder system contract
 * 3. zkSync API Client calls validateTransaction, which MUST update the nonce  
 * 4. zkSync API Client checks the nonce is updated
 * 5. zkSync API Client calls payForTransaction or preparePaymaster & validateAndPayForPaymasterTransaction
 * 6. zkSync API Client verifies that the bootloader gets paid
 * 
 * Phase 2 - Execution 
 * 7. zkSync API Client passed the validated txn to the main node / sequencer (as of today, these 2 are the same but hopefully they will be separate and decentralized in the future)
 * 8. the main node calls executeTransaction
 * 9. If a paymaster was user, the postTransaction is called
 */ 
contract ZkMinimalAccount is IAccount, Ownable {
    using MemoryTransactionHelper for Transaction;

    error ZkMinimalAccount__NotEnoughBalance();
    error ZkMinimalAccount__NotFromBootLoader();
    error ZkMinimalAccount__ExecutionFailed();
    error ZkMinimalAccount__PaymentFailed();
    error ZkMinimalAccount__InvalidSignature(); 

    /*//////////////////////////////////////////////////////////////
                            MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier requireFromBootloader() {
        if(msg.sender != BOOTLOADER_FORMAL_ADDRESS) {
            revert ZkMinimalAccount__NotFromBootLoader();
        }
        _;
    }

    constructor() Ownable(msg.sender) {}

    receive() external payable {}
    /*//////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice must increase nonce
     * @notice must validate transaction (owned signed the txn is validation criteria)
     * @notice also will check enough money in the account to pay for transaction
     */
    function validateTransaction(bytes32 /* _txHash */, bytes32 /* _suggestedSignedHash */, Transaction memory _transaction)
        external
        payable
        requireFromBootloader
        returns (bytes4 magic)
    {    
        return _validateTransaction(_transaction);
    }

    function executeTransaction(bytes32 /* _txHash */, bytes32 /* _suggestedSignedHash */, Transaction memory _transaction)
        external
        payable
    {
        _executeTransaction(_transaction);
    }

    function executeTransactionFromOutside(Transaction memory _transaction) external payable 
    {
        bytes4 magic = _validateTransaction(_transaction);
        if(magic != ACCOUNT_VALIDATION_SUCCESS_MAGIC){
            revert ZkMinimalAccount__InvalidSignature();
        }
        _executeTransaction(_transaction);
    }

    function payForTransaction(bytes32 /* _txHash */, bytes32 /* _suggestedSignedHash */, Transaction memory _transaction)
        external
        payable
    {
        bool success = _transaction.payToTheBootloader();
        if(!success) {
            revert ZkMinimalAccount__PaymentFailed();
        }
    }

    function prepareForPaymaster(bytes32 _txHash, bytes32 _possibleSignedHash, Transaction memory _transaction)
        external
        payable
    {}

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function _validateTransaction(Transaction memory _transaction) internal returns (bytes4 magic) {
        // call nonceHolder
        // increment nonce
        // call(x, y, z) -> systems contract call
        SystemContractsCaller.systemCallWithPropagatedRevert(
            uint32(gasleft()),
            address(NONCE_HOLDER_SYSTEM_CONTRACT),
            0,
            abi.encodeCall(INonceHolder.incrementMinNonceIfEquals, (_transaction.nonce))
        );
        
        // Check for fee to pay
        uint256 totalRequiredBalance = _transaction.totalRequiredBalance(); 
        if(totalRequiredBalance > address(this).balance){
            revert ZkMinimalAccount__NotEnoughBalance();
        }

        // Check the signature
        bytes32 txHash = _transaction.encodeHash();
        address signer = ECDSA.recover(txHash, _transaction.signature);
        bool isValidSigner = signer == owner();
        if (isValidSigner) {
            magic = ACCOUNT_VALIDATION_SUCCESS_MAGIC;
        } else {
            magic = bytes4(0);
        }

        // return the "magic" number 
        return magic;
    }
    function _executeTransaction(Transaction memory _transaction) internal {
        address to = address(uint160(_transaction.to));
        uint128 value = Utils.safeCastToU128(_transaction.value);
        bytes memory data = _transaction.data;

        if(to == address(DEPLOYER_SYSTEM_CONTRACT)){
            uint32 gas = Utils.safeCastToU32(gasleft());
            SystemContractsCaller.systemCallWithPropagatedRevert(gas, to, value, data);
        } else {
            bool success;
            assembly {
                success := call(gas(), to, value, add(data, 0x20), mload(data), 0, 0)
            }
            if(!success){
                revert ZkMinimalAccount__ExecutionFailed();
            }
        }
    }
}
