// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Game} from "../src/Game.sol";
import {Test, console2} from "forge-std/Test.sol";

contract Handler is Test {
    Game public game;

    address public currentUser;
    address[] public users;
    address deployer = makeAddr("deployer");


    constructor(Game _game) {
        game = _game;
    }

    function _getOrCreateUser() internal returns (address) {
        if (users.length == 0) {
            address user =
                address(uint160(uint256(keccak256(abi.encodePacked(block.timestamp, blockhash(block.number))))));
            users.push(user);
            return user;
        }

        // Choose a random existing user
        uint256 idx = uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao))) % users.length;
        return users[idx];
    }

    function claimThrone(uint256 amount) public payable {
        address caller = _getOrCreateUser();
        uint256 boundValue = bound(amount, game.claimFee(), 100 ether);
        vm.deal(caller, boundValue);
        currentUser = caller;
        vm.prank(caller);
        game.claimThrone{value: boundValue}();
    }

    function declareWinner() public {

        vm.warp(block.timestamp + game.gracePeriod() + 1);

        address winner = game.currentKing();
        vm.prank(address(this));
        game.declareWinner();

        currentUser = winner;

        vm.prank(deployer);
        game.resetGame();
        currentUser = address(0);
    }
}
