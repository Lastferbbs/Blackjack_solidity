//SPDX-Licence-Identifier: MIT
pragma solidity ^0.8.0;

contract BlackJack {
    mapping(address => uint256) public availableChips;

    uint256 public casinoBalance;
    address public owner;

    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert("Not owner");
        }
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function casinoDeposit() external payable onlyOwner {
        casinoBalance += msg.value;
    }

    function casinoWithdraw(uint256 withdraw_money) external onlyOwner {}

    function buyChips() external payable {}

    function withdrawMoney(uint256 cash) external {}

    function betWithChips(uint256 bet_size) external {}

    function hit() public {}

    function stand() public {}

    function double() public {}
}
