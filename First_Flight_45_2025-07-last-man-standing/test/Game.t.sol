// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {Game} from "../src/Game.sol";
import {Handler} from "../test/handler.t.sol";

contract GameTest is Test {
    Game public game;
    Handler public handler;

    address public deployer;
    address public player1;
    address public player2;
    address public player3;
    address public maliciousActor;

    // Initial game parameters for testing
    uint256 public constant INITIAL_CLAIM_FEE = 0.1 ether; // 0.1 ETH
    uint256 public constant GRACE_PERIOD = 1 days; // 1 day in seconds
    uint256 public constant FEE_INCREASE_PERCENTAGE = 10; // 10%
    uint256 public constant PLATFORM_FEE_PERCENTAGE = 5; // 5%

    function setUp() public {
        deployer = makeAddr("deployer");
        player1 = makeAddr("player1");
        player2 = makeAddr("player2");
        player3 = makeAddr("player3");
        maliciousActor = makeAddr("maliciousActor");

        vm.deal(deployer, 10 ether);
        vm.deal(player1, 10 ether);
        vm.deal(player2, 10 ether);
        vm.deal(player3, 10 ether);
        vm.deal(maliciousActor, 10 ether);

        vm.startPrank(deployer);
        game = new Game(INITIAL_CLAIM_FEE, GRACE_PERIOD, FEE_INCREASE_PERCENTAGE, PLATFORM_FEE_PERCENTAGE);
        vm.stopPrank();

        handler = new Handler(game);
        targetContract(address(handler));
    }

    function testConstructor_RevertInvalidGracePeriod() public {
        vm.expectRevert("Game: Grace period must be greater than zero.");
        new Game(INITIAL_CLAIM_FEE, 0, FEE_INCREASE_PERCENTAGE, PLATFORM_FEE_PERCENTAGE);
    }

    ///////////////////////////
    //// Integration Test /////
    //////////////////////////

    function test_MultipleUserEnteredAndWinnerDeclaredWinningsWithdrawn() public {
        vm.startPrank(player1); // Player 1 enters
        game.claimThrone{value: game.claimFee()}();
        assertEq(player1, game.currentKing());
        vm.stopPrank();

        vm.startPrank(player2); // Player 2 enters
        game.claimThrone{value: game.claimFee()}();
        assertEq(player2, game.currentKing());
        vm.stopPrank();

        vm.startPrank(player3); // Player 3 enters
        game.claimThrone{value: game.claimFee()}();
        assertEq(player3, game.currentKing());
        vm.stopPrank();

        vm.warp(block.timestamp + 86401 seconds);

        game.declareWinner(); //Winner Declared

        uint256 player3BalanceBefore = address(player3).balance;

        vm.startPrank(player3);
        game.withdrawWinnings(); // Winnings Withdrawn
        assertGt(address(player3).balance, player3BalanceBefore);
        assertEq(game.pendingWinnings(msg.sender), 0);
        vm.stopPrank();
    }

    function test_GameResetAfterGameEndAndWithdrawEarnings() public {
        test_MultipleUserEnteredAndWinnerDeclaredWinningsWithdrawn(); // Calling the test function to set the state for deployer to call reset.
        vm.startPrank(deployer);
        game.resetGame(); // Game reset called by deployer.
        assertEq(game.currentKing(), address(0));
        vm.stopPrank();

        vm.startPrank(deployer);
        uint256 deployerBalanceBfore = address(deployer).balance;
        game.withdrawPlatformFees();
        assertGt(address(deployer).balance, deployerBalanceBfore);
        vm.stopPrank();
    }

    function test_SendingLessClaimFeeThanRequired() public {
        vm.startPrank(player1);
        vm.expectRevert();
        game.claimThrone{value: 0.001 ether}();
        vm.stopPrank();
    }

    function test_DeclareWinnerWhenNoOneEnteredTheGameAndGracePeriodIsStillActive() public {
        vm.expectRevert();
        game.declareWinner();

        vm.startPrank(player1);
        game.claimThrone{value: game.claimFee()}();
        vm.stopPrank();

        vm.expectRevert();
        game.declareWinner();
    }

    function test_Getters() external {
        vm.startPrank(player1);
        game.claimThrone{value: game.claimFee()}();
        vm.stopPrank();

        console2.log("Remaining Time is:", game.getRemainingTime());
        console2.log("Contract balance is:", game.getContractBalance());
    }

    ////////////////////////////////
    //// Test Submitted as POC /////
    ////////////////////////////////

    function testAnyoneExceptCurrentKingCannotClaim_BugProof() public {
        console2.log("Current King is:", game.currentKing());
        vm.startPrank(player1);
        game.claimThrone{value: game.claimFee()}();
        assertEq(game.currentKing(), player1);
    }

    event GameEnded(address indexed winner, uint256 prizeAmount, uint256 timestamp, uint256 round);

    function test_GameEndedEmitsInCorrectPrizeAmount() public {
        // Arrange
        vm.startPrank(player1);
        game.claimThrone{value: game.claimFee()}(); // Assume this adds 1 ether to the pot

        vm.warp(block.timestamp + game.gracePeriod() + 1);

        // Expect the emit
        vm.expectEmit(true, false, false, false); // All indexed + non-indexed match
        emit GameEnded(game.currentKing(), game.pot(), block.timestamp, game.gameRound());

        // Act
        game.declareWinner();
    }

    function test_NoLogicForRefundOfExcessEthDeposited() public {
        console2.log("Balance of Player1 before claiming:", player1.balance);

        vm.startPrank(player1);
        uint256 excess = 5 ether;
        game.claimThrone{value: excess}(); // Overpaying claim fee
        vm.stopPrank();

        console2.log("Balance of Player1 after claiming:", player1.balance);

        assertEq(game.currentKing(), player1, "Player1 should be current king");
        assertGt(game.pot(), game.claimFee(), "Pot should include excess ETH"); // Confirm excess added to pot
    }

    function test_NoPayoutToPreviousKing() public {
        // player1 becomes king
        vm.startPrank(player1);
        game.claimThrone{value: game.claimFee()}();
        vm.stopPrank();

        // player2 becomes new king
        uint256 player1BalanceBefore = player1.balance;
        vm.startPrank(player2);
        game.claimThrone{value: game.claimFee()}();
        vm.stopPrank();
        uint256 player1BalanceAfter = player1.balance;

        // Assert no payout occurred to player1
        assertEq(player1BalanceAfter, player1BalanceBefore);
    }

    function test_SendingEthDirectToTheContract() public {
        uint256 gameContractBalanceBefore = address(game).balance;
        vm.startPrank(maliciousActor);
        (bool success,) = address(game).call{value: 1 ether}("");
        require(success, "Tx Failed");
        uint256 gameContractBalanceAfter = address(game).balance;
        assertGt(gameContractBalanceAfter, gameContractBalanceBefore);
    }

    function test_updatingGracePeriodMidGameByOwner() public {
        // Player1 starts the game
        vm.startPrank(player1);
        game.claimThrone{value: game.claimFee()}();
        assertEq(player1, game.currentKing());
        vm.stopPrank();

        // Store old game parameters
        uint256 gracePeriodBefore = game.gracePeriod();
        uint256 feeIncreasePercentageBefore = game.feeIncreasePercentage();
        uint256 platformFeePercentageBefore = game.platformFeePercentage();

        // Owner updates parameters during an active game
        vm.startPrank(deployer);
        game.updateGracePeriod(172800); // from 1 day to 2 days
        game.updateClaimFeeParameters(1 ether, 50); // claim fee to 1 ether & feeIncreasePercentage to 50%
        game.updatePlatformFeePercentage(50); // platform fee to 50%
        vm.stopPrank();

        // Assert the values were updated correctly
        assertGt(game.gracePeriod(), gracePeriodBefore);
        assertGt(game.feeIncreasePercentage(), feeIncreasePercentageBefore);
        assertGt(game.platformFeePercentage(), platformFeePercentageBefore);

        // Player2 joins under new game conditions
        vm.startPrank(player2);
        game.claimThrone{value: game.claimFee()}();
        assertEq(player2, game.currentKing());
        vm.stopPrank();
    }

    /////////////////////
    //// Fuzz Test //////
    /////////////////////

    function test_Fuzz_ClaimThrone(uint256 amount) external {
        vm.startPrank(player1);
        uint256 boundedValue = bound(amount, game.claimFee(), 10 ether);
        game.claimThrone{value: boundedValue}();
        assertEq(game.currentKing(), player1);
        vm.stopPrank();
    }

    //////////////////////////
    //// Invariant Test //////
    /////////////////////////

    function invariant_CurrentKingIsLastClaimer() public view {
        assertEq(game.currentKing(), handler.currentUser());
    }
}
