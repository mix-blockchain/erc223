pragma solidity ^0.5.12;

import "mix-item-dag/MixItemDagOneParentOnlyOwner.sol";
import "./MixTokenInterface.sol";
import "./MixTokenItemRegistry.sol";


/**
 * @title MixTokenBurn
 * @author Jonathan Brown <jbrown@mix-blockchain.org>
 * @dev Enable accounts to burn their tokens.
 */
contract MixTokenBurn {

    /**
     * Amount of tokens burned, linked to next most burned.
     */
    struct AccountBurnedLinked {
        address next;
        uint amount;
    }

    /**
     * Mapping of account to list of tokens that it has burned.
     */
    mapping (address => address[]) accountTokensBurnedList;

    /**
     * Mapping of token to mapping of account to AccountBurnedLinked.
     */
    mapping (address => mapping (address => AccountBurnedLinked)) tokenAccountBurned;

    /**
     * Mapping of account to list of itemIds that it has burned the token for.
     */
    mapping (address => bytes32[]) accountItemsBurnedList;

    /**
     * Mapping of itemId to mapping of account to quantity of tokens burned for the item.
     */
    mapping (bytes32 => mapping (address => AccountBurnedLinked)) itemAccountBurned;

    /**
     * Mapping of item to total burned for the item.
     */
    mapping (bytes32 => uint) itemBurnedTotal;

    /**
     * Address of token registry contract.
     */
    MixTokenItemRegistry tokenItemRegistry;

    /**
     * Address of contract linking content items to the token that can be burned for it.
     */
    MixItemDagOneParentOnlyOwner tokenItems;

    /**
     * @dev A token has been burned.
     * @param token Address of the token's contract.
     * @param itemId Item the token was burned for, or 0 for none.
     * @param account Address of the account burning its tokens.
     * @param amount Amount of tokens burned.
     */
    event BurnToken(MixTokenInterface indexed token, bytes32 indexed itemId, address indexed account, uint amount);

    /**
     * @dev Revert if amount is zero.
     * @param amount Amount that must not be zero.
     */
    modifier nonZero(uint amount) {
        require (amount != 0);
        _;
    }

    /**
     * @param _tokenItemRegistry Address of the MixTokenItemRegistry contract.
     * @param _tokenItems Address of the MixItemDagOneParentOnlyOwner contract.
     */
    constructor(MixTokenItemRegistry _tokenItemRegistry, MixItemDagOneParentOnlyOwner _tokenItems) public {
        // Store the address of the MixTokenItemRegistry contract.
        tokenItemRegistry = _tokenItemRegistry;
        // Store the address of the MixItemDagOneParentOnlyOwner contract.
        tokenItems = _tokenItems;
    }

    /**
     * @dev Get previous and old previous accounts for inserting into linked list.
     * @param accountBurned Linked list of how much each account has burned.
     * @param amount Amount that the the new entry will have.
     * @return prev Address of the entry preceeding the new entry.
     * @return oldPrev Address of the entry preceeding the old entry.
     */
    function _getPrev(mapping (address => AccountBurnedLinked) storage accountBurned, uint amount) internal view nonZero(amount) returns (address prev, address oldPrev) {
        // Get total.
        uint total = accountBurned[msg.sender].amount + amount;
        prev = address(0);
        // Search for first account that has burned less than sender.
        address next = accountBurned[address(0)].next;
        // accountBurned[0].amount == 0
        while (total <= accountBurned[next].amount) {
            prev = next;
            next = accountBurned[next].next;
        }
        // Is sender already in the list?
        if (accountBurned[msg.sender].amount == 0) {
            oldPrev = address(0);
        }
        else {
            // Search for account.
            oldPrev = prev;
            while (accountBurned[oldPrev].next != msg.sender) {
                oldPrev = accountBurned[oldPrev].next;
            }
        }
    }

    /**
     * @dev Get previous and old previous accounts for inserting burned tokens into tokenAccountBurned linked list.
     * @param token Token that is being burned.
     * @param amount Amount of the token that is being burned.
     * @return prev Address of the entry preceeding the new entry.
     * @return oldPrev Address of the entry preceeding the old entry.
     */
    function getBurnTokenPrev(MixTokenInterface token, uint amount) external view returns (address prev, address oldPrev) {
        (prev, oldPrev) = _getPrev(tokenAccountBurned[address(token)], amount);
    }

    /**
     * @dev Get previous and old previous accounts for inserting burned tokens for an item into both tokenAccountBurned and itemAccountBurned linked lists.
     * @param itemId Item having its token burned.
     * @param amount Amount of the token that is being burned.
     * @return tokenPrev Address of the entry preceeding the new entry in the tokenAccountBurned linked list.
     * @return tokenOldPrev Address of the entry preceeding the old entry in the tokenAccountBurned linked list.
     * @return itemPrev Address of the entry preceeding the new entry in the itemAccountBurned linked list.
     * @return itemOldPrev Address of the entry preceeding the old entry in the itemAccountBurned linked list.
     */
    function getBurnItemPrev(bytes32 itemId, uint amount) external view returns (address tokenPrev, address tokenOldPrev, address itemPrev, address itemOldPrev) {
        // Get token contract for item.
        address token = tokenItemRegistry.getToken(tokenItems.getParentId(itemId));
        // Get previous and old previous for tokenAccountBurned linked list.
        (tokenPrev, tokenOldPrev) = _getPrev(tokenAccountBurned[token], amount);
        // Get previous and old previous for itemAccountBurned linked list.
        (itemPrev, itemOldPrev) = _getPrev(itemAccountBurned[itemId], amount);
    }

    /**
     * @dev Insert amount burned into linked list.
     * @param accountBurned Linked list of how much each account has burned.
     * @param amount Amount of tokens burned.
     * @param prev Address of the entry preceeding the new entry.
     * @param oldPrev Address of the entry preceeding the old entry.
     */
    function _accountBurnedInsert(mapping (address => AccountBurnedLinked) storage accountBurned, uint amount, address prev, address oldPrev) internal {
        bool replace = false;
        // Is sender already in the list?
        if (accountBurned[msg.sender].amount > 0) {
            // Make sure oldPrev is correct.
            require (accountBurned[oldPrev].next == msg.sender, "Old previous is incorrect.");
            // Is it in the same position?
            if (prev == oldPrev) {
                replace = true;
            }
            else {
                // Remove sender from current position.
                accountBurned[oldPrev].next = accountBurned[msg.sender].next;
            }
        }
        // Get total burned by sender for this token.
        uint total = accountBurned[msg.sender].amount + amount;
        accountBurned[msg.sender].amount = total;
        // Check new previous.
        if (prev != address(0)) {
            require (total <= accountBurned[prev].amount, "Total burned must be less than or equal to previous account.");
        }
        if (!replace) {
            address next = accountBurned[prev].next;
            // Check new next.
            if (next != address(0)) {
                require (total > accountBurned[next].amount, "Total burned must be more than next account.");
            }
            accountBurned[prev].next = msg.sender;
            accountBurned[msg.sender].next = next;
        }
    }

    /**
     * @dev Record burning of tokens in linked list.
     * @param token Address of token being burned.
     * @param amount Amount of token being burned.
     * @param prev Address of the entry preceeding the new entry.
     * @param oldPrev Address of the entry preceeding the old entry.
     */
    function _burnToken(address token, uint amount, address prev, address oldPrev) internal {
        // Get accountBurned mapping.
        mapping (address => AccountBurnedLinked) storage accountBurned = tokenAccountBurned[token];
        // Update list of tokens burned by this account.
        if (accountBurned[msg.sender].amount == 0) {
            accountTokensBurnedList[msg.sender].push(token);
        }
        _accountBurnedInsert(accountBurned, amount, prev, oldPrev);
    }

    /**
     * @dev Record burning of tokens for item in linked list.
     * @param itemId Item having its token burned.
     * @param amount Amount of token being burned.
     * @param prev Address of the entry preceeding the new entry.
     * @param oldPrev Address of the entry preceeding the old entry.
     */
    function _burnItem(bytes32 itemId, uint amount, address prev, address oldPrev) internal {
        // Get accountBurned mapping.
        mapping (address => AccountBurnedLinked) storage accountBurned = itemAccountBurned[itemId];
        // Update list of items burned by this account.
        if (accountBurned[msg.sender].amount == 0) {
            accountItemsBurnedList[msg.sender].push(itemId);
        }
        _accountBurnedInsert(accountBurned, amount, prev, oldPrev);
    }

    /**
     * @dev Burn sender's tokens.
     * @param token Address of the token's contract.
     * @param amount Amount of tokens burned.
     * @param prev Address of the entry preceeding the new entry.
     * @param oldPrev Address of the entry preceeding the old entry.
     */
    function burnToken(MixTokenInterface token, uint amount, address prev, address oldPrev) external nonZero(amount) {
        // Transfer the tokens to this contract.
        // Wrap with require () in case the token contract returns false on error instead of throwing.
        require (token.transferFrom(msg.sender, address(this), amount), "Token transfer failed.");
        // Record the tokens as burned.
        _burnToken(address(token), amount, prev, oldPrev);
        // Emit the event.
        emit BurnToken(token, 0, msg.sender, amount);
    }

    /**
     * @dev Burn sender's tokens for a specific item.
     * @param itemId Item to burn this token for.
     * @param amount Amount of tokens burned.
     * @param tokenPrev Address of the entry preceeding the new entry in the tokenAccountBurned linked list.
     * @param tokenOldPrev Address of the entry preceeding the old entry in the tokenAccountBurned linked list.
     * @param itemPrev Address of the entry preceeding the new entry in the itemAccountBurned linked list.
     * @param itemOldPrev Address of the entry preceeding the old entry in the itemAccountBurned linked list.
     */
    function burnItem(bytes32 itemId, uint amount, address tokenPrev, address tokenOldPrev, address itemPrev, address itemOldPrev) external nonZero(amount) {
        // Get token contract for item.
        MixTokenInterface token = MixTokenInterface(tokenItemRegistry.getToken(tokenItems.getParentId(itemId)));
        require (address(token) != address(0), "Item does not have a token to burn.");
        // Transfer the tokens to this contract.
        // Wrap with require () in case the token contract returns false on error instead of throwing.
        require (token.transferFrom(msg.sender, address(this), amount), "Token transfer failed.");
        // Record the tokens as burned.
        _burnToken(address(token), amount, tokenPrev, tokenOldPrev);
        _burnItem(itemId, amount, itemPrev, itemOldPrev);
        // Update total burned for this item.
        itemBurnedTotal[itemId] += amount;
        // Emit the event.
        emit BurnToken(token, itemId, msg.sender, amount);
    }

    /**
     * @dev Get the amount of tokens an account has burned.
     * @param account Address of the account.
     * @param token Address of the token contract.
     * @return Amount of these tokens that this account has burned.
     */
    function getAccountTokenBurned(address account, MixTokenInterface token) external view returns (uint) {
        return tokenAccountBurned[address(token)][account].amount;
    }

    /**
     * @dev Get the amount of tokens an account has burned for an item.
     * @param account Address of the account.
     * @param itemId Item to get the amount of tokens account has burned for it.
     * @return Amount of these tokens that this account has burned for the item.
     */
    function getAccountItemBurned(address account, bytes32 itemId) external view returns (uint) {
        return itemAccountBurned[itemId][account].amount;
    }

    /**
     * @dev Get number of different tokens an account has burned.
     * @param account Account to get the number of different tokens burned.
     * @return Number of different tokens account has burned.
     */
    function getAccountTokensBurnedCount(address account) external view returns (uint) {
        return accountTokensBurnedList[account].length;
    }

    /**
     * @dev Get list of tokens that an account has burned.
     * @param account Account to get which tokens it has burned.
     * @param offset Offset to start results from.
     * @param limit Maximum number of results to return. 0 for unlimited.
     * @return tokens List of tokens the account has burned.
     * @return amounts Amount of each token that was burned by account.
     */
    function getAccountTokensBurned(address account, uint offset, uint limit) external view returns (address[] memory tokens, uint[] memory amounts) {
        // Get tokensBurned mapping.
        address[] storage tokensBurned = accountTokensBurnedList[account];
        uint _limit = 0;
        // Check if offset is beyond the end of the array.
        if (offset < tokensBurned.length) {
            // Check how many itemIds we can retrieve.
            if (limit == 0 || offset + limit > tokensBurned.length) {
                _limit = tokensBurned.length - offset;
            }
            else {
                _limit = limit;
            }
        }
        // Allocate memory arrays.
        tokens = new address[](_limit);
        amounts = new uint[](_limit);
        // Populate memory array.
        for (uint i = 0; i < _limit; i++) {
            tokens[i] = tokensBurned[offset + i];
            amounts[i] = tokenAccountBurned[tokens[i]][account].amount;
        }
    }

    /**
     * @dev Get accounts that have burned.
     * @param accountBurned Linked list of how much each account has burned.
     * @param offset Offset to start results from.
     * @param limit Maximum number of results to return.
     * @return accounts List of accounts that burned the token.
     * @return amounts Amount of token each account burned.
     */
    function _getAccountsBurned(mapping (address => AccountBurnedLinked) storage accountBurned, uint offset, uint limit) internal view returns (address[] memory accounts, uint[] memory amounts) {
        // Find the account at offset.
        address start = accountBurned[address(0)].next;
        uint i = 0;
        while (start != (address(0)) && i++ < offset) {
            start = accountBurned[start].next;
        }
        // Check how many accounts we can retrieve.
        address account = start;
        uint _limit = 0;
        while (account != address(0) && _limit < limit) {
            account = accountBurned[account].next;
            _limit++;
        }
        // Allocate return variables.
        accounts = new address[](_limit);
        amounts = new uint[](_limit);
        // Populate return variables.
        account = start;
        i = 0;
        while (i < _limit) {
            accounts[i] = account;
            amounts[i++] = accountBurned[account].amount;
            account = accountBurned[account].next;
        }
    }

    /**
     * @dev Get accounts that have burned a token.
     * @param token Token to get accounts that have burned it.
     * @param offset Offset to start results from.
     * @param limit Maximum number of results to return.
     * @return accounts List of accounts that burned the token.
     * @return amounts Amount of token each account burned.
     */
    function getTokenAccountsBurned(address token, uint offset, uint limit) external view returns (address[] memory accounts, uint[] memory amounts) {
        // Get accountBurned mapping.
        mapping (address => AccountBurnedLinked) storage accountBurned = tokenAccountBurned[token];
        // Get accounts and corresponding amounts.
        (accounts, amounts) = _getAccountsBurned(accountBurned, offset, limit);
    }

    /**
     * @dev Get number of items an account has burned tokens for.
     * @param account Account to check.
     * @return Number of items account has burned tokens for.
     */
    function getAccountItemsBurnedCount(address account) external view returns (uint) {
        return accountItemsBurnedList[account].length;
    }

    /**
     * @dev Get list of items that an account has burned tokens for.
     * @param account Account to check which items it has burned tokens for.
     * @param offset Offset to start results from.
     * @param limit Maximum number of results to return. 0 for unlimited.
     * @return itemIds List of itemIds for items account has burned tokens for.
     * @return amounts Amount of each token that was burned for each item by account.
     */
    function getAccountItemsBurned(address account, uint offset, uint limit) external view returns (bytes32[] memory itemIds, uint[] memory amounts) {
        // Get itemsBurned mapping.
        bytes32[] storage itemsBurned = accountItemsBurnedList[account];
        uint _limit = 0;
        // Check if offset is beyond the end of the array.
        if (offset < itemsBurned.length) {
            // Check how many itemIds we can retrieve.
            if (limit == 0 || offset + limit > itemsBurned.length) {
                _limit = itemsBurned.length - offset;
            }
            else {
                _limit = limit;
            }
        }
        // Allocate memory arrays.
        itemIds = new bytes32[](_limit);
        amounts = new uint[](_limit);
        // Populate memory array.
        for (uint i = 0; i < _limit; i++) {
            itemIds[i] = itemsBurned[offset + i];
            amounts[i] = itemAccountBurned[itemIds[i]][account].amount;
        }
    }

    /**
     * @dev Get accounts that have burned tokens for an item.
     * @param itemId Item to get accounts for.
     * @param offset Offset to start results from.
     * @param limit Maximum number of results to return.
     * @return accounts List of accounts that burned tokens for the item.
     * @return amounts Amount of token each account burned for the item.
     */
    function getItemAccountsBurned(bytes32 itemId, uint offset, uint limit) external view returns (address[] memory accounts, uint[] memory amounts) {
        // Get accountBurned mapping.
        mapping (address => AccountBurnedLinked) storage accountBurned = itemAccountBurned[itemId];
        // Get accounts and corresponding amounts.
        (accounts, amounts) = _getAccountsBurned(accountBurned, offset, limit);
    }

    /**
     * @dev Get total amount of tokens that were burned for an item.
     * @param itemId Item to get amount of tokens burned for.
     * @return Total amount of tokens that have been burned for the item.
     */
    function getItemBurnedTotal(bytes32 itemId) external view returns (uint) {
        return itemBurnedTotal[itemId];
    }

}
