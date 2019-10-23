pragma solidity ^0.5.11;

import "mix-item-dag/MixItemDagOneParent.sol";
import "./MixTokenInterface.sol";
import "./MixTokenRegistry.sol";


/**
 * @title MixTokenBurn
 * @author Jonathan Brown <jbrown@mix-blockchain.org>
 * @dev Enable accounts to burn their tokens.
 */
contract MixTokenBurn {

    /**
     * Amount of tokens burned, linked to previous and next most burned.
     */
    struct AccountBurnedLinked {
        address prev;
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
    MixTokenRegistry tokenRegistry;

    /**
     * Address of contract linking content items to the token that can be burned for it.
     */
    MixItemDagOneParent tokenItems;

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
     * @param _tokenRegistry Address of the MixTokenRegistry contract.
     * @param _tokenItems Address of the MixItemDagOneParent contract.
     */
    constructor(MixTokenRegistry _tokenRegistry, MixItemDagOneParent _tokenItems) public {
        // Store the address of the MixItemStoreRegistry contract.
        tokenRegistry = _tokenRegistry;
        // Store the address of the MixItemDagOneParent contract.
        tokenItems = _tokenItems;
    }

    /**
     * @dev Get previous and next accounts for inserting into linked list.
     * @param accountBurned Linked list of how much each account has burned.
     * @param amount Amount that the the new entry will have.
     * @return prev Address of the entry preceeding the new entry.
     * @return next Address of the entry after the new entry.
     */
    function _getPrevNext(mapping (address => AccountBurnedLinked) storage accountBurned, uint amount) internal view nonZero(amount) returns (address prev, address next) {
        // Get total.
        uint total = accountBurned[msg.sender].amount + amount;
        next = accountBurned[address(0)].next;
        // Search for first account that has burned less than sender.
        // accountBurned[0].amount == 0
        while (total <= accountBurned[next].amount) {
            next = accountBurned[next].next;
        }
        prev = accountBurned[next].prev;
        // Are we in the same position?
        if (next == msg.sender) {
            next = accountBurned[msg.sender].next;
        }
    }

    /**
     * @dev Get previous and next accounts for inserting burned tokens into tokenAccountBurned linked list.
     * @param token Token that is being burned.
     * @param amount Amount of the token that is being burned.
     * @return prev Address of the entry preceeding the new entry.
     * @return next Address of the entry after the new entry.
     */
    function getBurnTokenPrevNext(MixTokenInterface token, uint amount) external view returns (address prev, address next) {
        (prev, next) = _getPrevNext(tokenAccountBurned[address(token)], amount);
    }

    /**
     * @dev Get previous and next accounts for inserting burned tokens for an item into both tokenAccountBurned and itemAccountBurned linked lists.
     * @param itemId Item having its token burned.
     * @param amount Amount of the token that is being burned.
     * @return tokenPrev Address of the entry preceeding the new entry in the tokenAccountBurned linked list.
     * @return tokenNext Address of the entry after the new entry in the tokenAccountBurned linked list.
     * @return itemPrev Address of the entry preceeding the new entry in the itemAccountBurned linked list.
     * @return itemNext Address of the entry after the new entry in the itemAccountBurned linked list.
     */
    function getBurnItemPrevNext(bytes32 itemId, uint amount) external view returns (address tokenPrev, address tokenNext, address itemPrev, address itemNext) {
        // Get token contract for item.
        address token = tokenRegistry.getToken(tokenItems.getParentId(itemId));
        // Get previous and next for tokenAccountBurned linked list.
        (tokenPrev, tokenNext) = _getPrevNext(tokenAccountBurned[token], amount);
        // Get previous and next for itemAccountBurned linked list.
        (itemPrev, itemNext) = _getPrevNext(itemAccountBurned[itemId], amount);
    }

    /**
     * @dev Insert amount burned into linked list.
     * @param accountBurned Linked list of how much each account has burned.
     * @param amount Amount of tokens burned.
     * @param prev Address of the entry preceeding the new entry.
     * @param next Address of the entry after the new entry.
     */
    function _accountBurnedInsert(mapping (address => AccountBurnedLinked) storage accountBurned, uint amount, address prev, address next) internal {
        // Get total burned by sender for this token.
        uint total = accountBurned[msg.sender].amount + amount;
        // Check new previous.
        if (prev != address(0)) {
            require (total <= accountBurned[prev].amount, "Total burned must be less than or equal to previous account.");
        }
        // Check new next.
        if (next != address(0)) {
            require (total > accountBurned[next].amount, "Total burned must be more than next account.");
        }
        bool alreadyExists = accountBurned[msg.sender].amount != 0;
        accountBurned[msg.sender].amount = total;
        if (alreadyExists) {
            // Is the account staying in the same position?
            if (prev == accountBurned[msg.sender].prev && next == accountBurned[msg.sender].next) {
                // Nothing more to do.
                return;
            }
            // Remove account links from list.
            accountBurned[accountBurned[msg.sender].prev].next = accountBurned[msg.sender].next;
            accountBurned[accountBurned[msg.sender].next].prev = accountBurned[msg.sender].prev;
        }
        // Check there is no gap between prev and next.
        require (accountBurned[prev].next == next, "Next must be directly after previous.");
        accountBurned[prev].next = msg.sender;
        accountBurned[next].prev = msg.sender;
        accountBurned[msg.sender].prev = prev;
        accountBurned[msg.sender].next = next;
    }

    /**
     * @dev Record burning of tokens in linked list.
     * @param token Address of token being burned.
     * @param amount Amount of token being burned.
     * @param prev Address of the entry preceeding the new entry.
     * @param next Address of the entry after the new entry.
     */
    function _burnToken(address token, uint amount, address prev, address next) internal {
        // Get accountBurned mapping.
        mapping (address => AccountBurnedLinked) storage accountBurned = tokenAccountBurned[token];
        // Update list of tokens burned by this account.
        if (accountBurned[msg.sender].amount == 0) {
            accountTokensBurnedList[msg.sender].push(token);
        }
        _accountBurnedInsert(accountBurned, amount, prev, next);
    }

    /**
     * @dev Record burning of tokens for item in linked list.
     * @param itemId Item having its token burned.
     * @param amount Amount of token being burned.
     * @param prev Address of the entry preceeding the new entry.
     * @param next Address of the entry after the new entry.
     */
    function _burnItem(bytes32 itemId, uint amount, address prev, address next) internal {
        // Get accountBurned mapping.
        mapping (address => AccountBurnedLinked) storage accountBurned = itemAccountBurned[itemId];
        // Update list of items burned by this account.
        if (accountBurned[msg.sender].amount == 0) {
            accountItemsBurnedList[msg.sender].push(itemId);
        }
        _accountBurnedInsert(accountBurned, amount, prev, next);
    }

    /**
     * @dev Burn sender's tokens.
     * @param token Address of the token's contract.
     * @param amount Amount of tokens burned.
     * @param prev Address of the entry preceeding the new entry.
     * @param next Address of the entry after the new entry.
     */
    function burnToken(MixTokenInterface token, uint amount, address prev, address next) external nonZero(amount) {
        // Transfer the tokens to this contract.
        // Wrap with require () in case the token contract returns false on error instead of throwing.
        require (token.transferFrom(msg.sender, address(this), amount), "Token transfer failed.");
        // Record the tokens as burned.
        _burnToken(address(token), amount, prev, next);
        // Emit the event.
        emit BurnToken(token, 0, msg.sender, amount);
    }

    /**
     * @dev Burn sender's tokens for a specific item.
     * @param itemId Item to burn this token for.
     * @param amount Amount of tokens burned.
     * @param tokenPrev Address of the entry preceeding the new entry in the tokenAccountBurned linked list.
     * @param tokenNext Address of the entry after the new entry in the tokenAccountBurned linked list.
     * @param itemPrev Address of the entry preceeding the new entry in the itemAccountBurned linked list.
     * @param itemNext Address of the entry after the new entry in the itemAccountBurned linked list.
     */
    function burnItem(bytes32 itemId, uint amount, address tokenPrev, address tokenNext, address itemPrev, address itemNext) external nonZero(amount) {
        // Get token contract for item.
        MixTokenInterface token = MixTokenInterface(tokenRegistry.getToken(tokenItems.getParentId(itemId)));
        require (address(token) != address(0), "Item does not have a token to burn.");
        // Transfer the tokens to this contract.
        // Wrap with require () in case the token contract returns false on error instead of throwing.
        require (token.transferFrom(msg.sender, address(this), amount), "Token transfer failed.");
        // Record the tokens as burned.
        _burnToken(address(token), amount, tokenPrev, tokenNext);
        _burnItem(itemId, amount, itemPrev, itemNext);
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
        // Check if offset is beyond the end of the array.
        if (offset >= tokensBurned.length) {
            return (new address[](0), new uint[](0));
        }
        // Check how many itemIds we can retrieve.
        uint _limit;
        if (limit == 0 || offset + limit > tokensBurned.length) {
            _limit = tokensBurned.length - offset;
        }
        else {
            _limit = limit;
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
        // Check if offset is beyond the end of the array.
        if (offset >= itemsBurned.length) {
            return (new bytes32[](0), new uint[](0));
        }
        // Check how many itemIds we can retrieve.
        uint _limit;
        if (limit == 0 || offset + limit > itemsBurned.length) {
            _limit = itemsBurned.length - offset;
        }
        else {
            _limit = limit;
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
