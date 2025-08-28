// SPDX-License-Identifier: MIT
// @dev This contract has been adapted to fit with foundry
pragma solidity ^0.8.20;

/**
 * 这个合约是 一个带有 ERC677 功能的 LINK Token 实现，
 * 可以在转账时附带数据并触发合约回调
 * 主要用于 Chainlink 等预言机系统中，让代币转账同时携带指令数据。
*/
import {ERC20} from "@solmate/tokens/ERC20.sol";

interface ERC677Receiver {
    function onTokenTransfer(address _sender, uint256 _value, bytes memory _data) external;
}

contract LinkToken is ERC20 {
    uint256 constant INITIAL_SUPPLY = 1000000000000000000000000;
    uint8 constant DECIMALS = 18;

    constructor() ERC20("LinkToken", "LINK", DECIMALS) {
        _mint(msg.sender, INITIAL_SUPPLY);
    }

    function mint(address to, uint256 value) public {
        _mint(to, value);
    }

    event Transfer(address indexed from, address indexed to, uint256 value, bytes data);

    /**
     * @dev transfer token to a contract address with additional data if the recipient is a contact.
     * @param _to The address to transfer to.
     * @param _value The amount to be transferred.
     * @param _data The extra data to be passed to the receiving contract.
     */
    function transferAndCall(address _to, uint256 _value, bytes memory _data) public virtual returns (bool success) {
        super.transfer(_to, _value);
        // emit Transfer(msg.sender, _to, _value, _data);
        emit Transfer(msg.sender, _to, _value, _data);
        if (isContract(_to)) {
            contractFallback(_to, _value, _data);
        }
        return true;
    }

    // PRIVATE

    function contractFallback(address _to, uint256 _value, bytes memory _data) private {
        ERC677Receiver receiver = ERC677Receiver(_to);
        receiver.onTokenTransfer(msg.sender, _value, _data);
    }

    function isContract(address _addr) private view returns (bool hasCode) {
        uint256 length;
        assembly {
            length := extcodesize(_addr)
        }
        return length > 0;
    }
}
/**
 * ERC677 的扩展功能 —— transferAndCall
 * 在转账的同时，可以带上 bytes _data 额外数据，并且如果接收方是合约，会自动回调：receiver.onTokenTransfer(msg.sender, _value, _data);
 * 相当于 Token + callback 机制，方便合约在接收到代币时立刻执行逻辑（类似 ERC777 的 tokensReceived，或 ETH 的 receive()）。
 * 事件扩展
 * 定义了一个扩展版的 Transfer 事件，可以带上额外的 bytes data。
 * 这样 DApp 或预言机合约可以监听到 带数据的转账。
*/