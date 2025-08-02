
# 🔎 Audit Findings: First Flight 45------>Last Man Standing

Audit Date: 31st July 2025 - 02nd Aug 2025 

Reviewed by: Gakarot

---

## ✅ Summary

| Type      | Count |
|-----------|-------|
| High      | 4     |
| Medium    | X     |
| Low       | 2     |
| Gas       | X     |
| Informational | X |

---


# [H-1] Game::claimThrone() Permanently Locks Throne Due to Faulty Require Check


## Root

A faulty require check in the Game::claimThrone() function that prevents anyone including non-kings from claiming the throne.

## Impact

**No one can become the king** the core functionality of the game is blocked permanently.

## Description

**Normal Behavior**
Any user should be able to claim the throne by sending the required `claimFee()` and become the `currentKing`. Only the `currentKing` should be restricted from calling `claimThrone()` again to avoid redundant updates.

**Bug**:\
In the current implementation, even the **first user to call** **`claimThrone()`** gets blocked by the `require` condition because the contract incorrectly assumes `currentKing == msg.sender` **before** the first successful claim. As a result, no one can claim the throne, making the game unplayable.

```Solidity
    function claimThrone() external payable gameNotEnded nonReentrant {
        require(msg.value >= claimFee, "Game: Insufficient ETH sent to claim the throne.");
      @>require(msg.sender == currentKing, "Game: You are already the king. No need to re-claim.");

        uint256 sentAmount = msg.value;
        uint256 previousKingPayout = 0;
        uint256 currentPlatformFee = 0;
        uint256 amountToPot = 0;

        // Calculate platform fee
        currentPlatformFee = (sentAmount * platformFeePercentage) / 100;

        // Defensive check to ensure platformFee doesn't exceed available amount after previousKingPayout
        if (currentPlatformFee > (sentAmount - previousKingPayout)) {
            currentPlatformFee = sentAmount - previousKingPayout;
        }
        platformFeesBalance = platformFeesBalance + currentPlatformFee;

        // Remaining amount goes to the pot
        amountToPot = sentAmount - currentPlatformFee;
        pot = pot + amountToPot;

        // Update game state
        currentKing = msg.sender;
        lastClaimTime = block.timestamp;
        playerClaimCount[msg.sender] = playerClaimCount[msg.sender] + 1;
        totalClaims = totalClaims + 1;

        // Increase the claim fee for the next player
        claimFee = claimFee + (claimFee * feeIncreasePercentage) / 100;

        emit ThroneClaimed(
            msg.sender,
            sentAmount,
            claimFee,
            pot,
            block.timestamp
        );
    }
```

## Risk

**Likelihood**: HIGH

* This bug **always occurs on the first claim**, preventing anyone from participating.

* The game becomes **immediately unusable on deployment**.

**Impact**: HIGH

* No player can ever become the `currentKing`.

* Game flow is completely broken; users are blocked from interacting even if the fee is correct.

## Proof of Concept

```Solidity
function testAnyoneExceptCurrentKingCannotClaim_BugProof() public {
    vm.prank(player1);
    game.claimThrone{value: game.claimFee()}();
    assertEq(game.currentKing(), player1); // Fails here due to require reverting as address(0) is the current king.
}
// So the whole game just breaks down just after deploying because as currentKing will be address(0) so no one can claim the throne.

```

## Recommended Mitigation

```diff
- require(msg.sender == currentKing, "You are already the king. No need to re-claim.");
+ require(currentKing == address(0) || msg.sender != currentKing, "You are already the king. No need to re-claim.");
// Just correcting the require logic will do it.
```

---

# [H-2] No refund after overpaying ETH for claiming throne in `Game::claimThrone()`

## Root Cause

The `Game::claimThrone()` function lacks logic to validate or refund excess ETH sent by the caller. It only checks if the sent amount is >= claimFee() but does not enforce exact match or return the excess.

***

## Description

The `Game::claimThrone()` function does not check if the user has overpaid. Any ETH sent above the `Game::claimFee` is silently accepted and added to the `pot`, which may not be the intended user experience.

This could confuse users and lead to accidental overpayments. If this behavior is not intentional, it should be mitigated.

```solidity
    function claimThrone() external payable gameNotEnded nonReentrant {
        require(msg.value >= claimFee, "Game: Insufficient ETH sent to claim the throne.");
        // @audit Corrected the require statement logic for testing further.
        require(msg.sender != currentKing, "Game: You are already the king. No need to re-claim.");

        uint256 sentAmount = msg.value;
        uint256 previousKingPayout = 0;
        uint256 currentPlatformFee = 0;
        uint256 amountToPot = 0;

        // Calculate platform fee
        currentPlatformFee = (sentAmount * platformFeePercentage) / 100;

        // Defensive check to ensure platformFee doesn't exceed available amount after previousKingPayout
        if (currentPlatformFee > (sentAmount - previousKingPayout)) {
            currentPlatformFee = sentAmount - previousKingPayout;
        }
        platformFeesBalance = platformFeesBalance + currentPlatformFee;

        // Remaining amount goes to the pot
        amountToPot = sentAmount - currentPlatformFee;
        pot = pot + amountToPot;

        // Update game state
        currentKing = msg.sender;
        lastClaimTime = block.timestamp;
        playerClaimCount[msg.sender] = playerClaimCount[msg.sender] + 1;
        totalClaims = totalClaims + 1;

        // Increase the claim fee for the next player
        claimFee = claimFee + (claimFee * feeIncreasePercentage) / 100;

        emit ThroneClaimed(
            msg.sender,
            sentAmount,
            claimFee,
            pot,
            block.timestamp
        );
    }
```

***

## Impact

* **User Overpayment:** Users might mistakenly send more ETH than required, expecting a refund.

* **Poor UX:** Lack of feedback or refund can lead to user dissatisfaction.

* **Implied Griefing:** A malicious dApp frontend or social engineering could trick users into overpaying.

* **Accounting Confusion:** Pot balance may include ETH not intentionally contributed, complicating audits or payouts.

***

## Proof of Concept (PoC)

```solidity
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
```

***

## Recommended Mitigation:

**Option 1:** Enforce Exact ETH Match

Require the sender to send exactly the required fee:

```solidity
require(msg.value == claimFee(), "Game: Exact claim fee required");

```

**Pros:**

* Clean accounting pot only grows from actual fees.

* Prevents accidental overpayments.

* More predictable for off-chain UIs or integrations.

**Cons:**

* Might cause unnecessary revert if the user accidentally overpays.

* Can break composability with contracts that can't control exact ETH amounts.

* Breaks with sendValue() patterns or fallback-based UX.

***

**Option 2:** Accept overpayments but refund the difference:

```solidity
uint256 fee = claimFee();
require(msg.value >= fee, "Game: Insufficient claim fee");

uint256 excess = msg.value - fee;
if (excess > 0) {
    (bool success, ) = msg.sender.call{value: excess}("");
    require(success, "Game: Refund failed");
}

```

**Pros:**

* Flexible UX users can overpay without losing funds.

* Safer for integrations, wallets, or bundlers.

* Maintains predictable pot growth.

**Cons:**

* Adds external call risk (reentrancy-safe in this case since state updated before call, but still needs attention).

* Refunds might fail if msg.sender is a contract with fallback issues (can be mitigated with pull-based refunds if needed).

***

### Severity: High

* Silent loss of funds for users who **accidentally overpay**.

* No event logs for excess ETH tracking or debugging is difficult.

* Potential griefing vector: An attacker can **inflate the pot size** by repeatedly overpaying, making reclaiming economically infeasible for others (soft **DoS**).

* Trust issues for wallet integrations or relayers expecting precise fee mechanics.


---

# [H-3] `Claim::claimThrone()` missing payout to previous king

## Root Cause

In the `claimThrone()` function, a comment states:

```solidity
// If there's a previous king, a small portion of the new claim fee is sent to them.

```

But this logic is not implemented. Instead, the full `msg.value - platformFee` is added to the pot, and the previous king never receives any payout.

***

## Description

The `Game::claimThrone()` function includes a comment indicating that a portion of the claim fee should be sent to the previous king as a reward. However, this logic is completely missing in the actual implementation. Instead, the full msg.`value - platformFee` is added to the pot, and the dethroned king receives nothing, breaking the intended game mechanics.

This introduces a mismatch between expectations and reality, especially if users were led to believe (via UI/comments/announcements) that dethroned kings will be rewarded. The lack of such reward removes any economic incentive to compete, discouraging participation and possibly leading to centralization or inactivity.

```solidity
    function claimThrone() external payable gameNotEnded nonReentrant {
        require(msg.value >= claimFee, "Game: Insufficient ETH sent to claim the throne.");
        // @audit Corrected the require statement logic for testing further.
        require(msg.sender != currentKing, "Game: You are already the king. No need to re-claim.");

        uint256 sentAmount = msg.value;
@>      uint256 previousKingPayout = 0;
        uint256 currentPlatformFee = 0;
        uint256 amountToPot = 0;

        // Calculate platform fee
        currentPlatformFee = (sentAmount * platformFeePercentage) / 100;

        // Defensive check to ensure platformFee doesn't exceed available amount after previousKingPayout
        if (currentPlatformFee > (sentAmount - previousKingPayout)) {
            currentPlatformFee = sentAmount - previousKingPayout;
        }
        platformFeesBalance = platformFeesBalance + currentPlatformFee;

        // Remaining amount goes to the pot
        amountToPot = sentAmount - currentPlatformFee;
        pot = pot + amountToPot;

        // Update game state
        currentKing = msg.sender;
        lastClaimTime = block.timestamp;
        playerClaimCount[msg.sender] = playerClaimCount[msg.sender] + 1;
        totalClaims = totalClaims + 1;

        // Increase the claim fee for the next player
        claimFee = claimFee + (claimFee * feeIncreasePercentage) / 100;

        emit ThroneClaimed(
            msg.sender,
            sentAmount,
            claimFee,
            pot,
            block.timestamp
        );
    }
```

***

## Impact

**Economic incentive flaw:** Being dethroned has no reward, which can discourage users from participating.

Creates a mismatch between expected reward flow (as hinted in the comment or UI) and actual smart contract logic.

Reduces game attractiveness and can break trust if off-chain frontends claim there's a payout.

Can be considered loss of user funds if users were expecting a return on getting dethroned.

***

## Proof of Concept (PoC)

```solidity
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
```

***

## Recommended Mitigation:

**Implement logic to pay a small reward to the previous king**

```solidity
address previousKing = currentKing;

// Handle payout to previous king
if (previousKing != address(0)) {
    uint256 rewardToPrevious = pot / 10; // 10% reward
    pot -= rewardToPrevious; // Important: subtract reward from pot
    (bool sent, ) = payable(previousKing).call{value: rewardToPrevious}("");
    require(sent, "Reward payout failed");
}

```

***

### Severity: High

* Loss of incentive: Users may avoid participation once they realize there's no payout after losing the throne.

* Trust issue: Off-chain users and UIs expecting a reward will find the protocol misleading.

* Potential loss of funds: Players may assume they’ll get some reward and spend ETH accordingly.

* Game disruption: The competitive loop of the game (claim → dethrone → reward) breaks, turning the game into a one-way ETH sink.

---

# [H-4] Critical Game Parameters Can Be Updated Mid-Game by Owner, Leading to Centralization Risks and Unfair Gameplay

## Root Cause

All owner update functions `Game::updateGracePeriod()`, `Game::updateClaimFeeParameters()`, and `Game::updatePlatformFeePercentage()` lack any restriction to prevent them from being called while a game is active. This allows the contract owner to manipulate core parameters at any time. Any ability to change it during an ongoing game introduces **centralization risk and violates the expected fairness for participants**.

***

## Description

The following functions can be arbitrarily called by the owner while a game is still ongoing:

**Game::updateGracePeriod(uint256 \_newGracePeriod)**

**Game::updateClaimFeeParameters(uint256 \_newInitialClaimFee, uint256 \_newFeeIncreasePercentage)**

**Game::updatePlatformFeePercentage(uint256 \_newPlatformFeePercentage)**

None of these check whether the game is currently active or has ended. As a result, any of these parameters can be modified during an ongoing round to:

* Favor a specific player.

* Disrupt timing expectations.

* Or maximize platform profits at the expense of players.

Such actions violate the trustless and fair competition expectations of on-chain games.

```solidity
    function updateGracePeriod(uint256 _newGracePeriod) external onlyOwner {
        require(_newGracePeriod > 0, "Game: New grace period must be greater than zero.");
        gracePeriod = _newGracePeriod;
        emit GracePeriodUpdated(_newGracePeriod);
    }

    function updateClaimFeeParameters(uint256 _newInitialClaimFee, uint256 _newFeeIncreasePercentage)
        external
        onlyOwner
        isValidPercentage(_newFeeIncreasePercentage)
    {
        require(_newInitialClaimFee > 0, "Game: New initial claim fee must be greater than zero.");
        initialClaimFee = _newInitialClaimFee;
        feeIncreasePercentage = _newFeeIncreasePercentage;
        emit ClaimFeeParametersUpdated(_newInitialClaimFee, _newFeeIncreasePercentage);
    }

    function updatePlatformFeePercentage(uint256 _newPlatformFeePercentage)
        external
        onlyOwner
        isValidPercentage(_newPlatformFeePercentage)
    {
        platformFeePercentage = _newPlatformFeePercentage;
        emit PlatformFeePercentageUpdated(_newPlatformFeePercentage);
    }
```

***

## Impact

The ability to change gameplay fees, reward timing, or platform fee percentages mid-round breaks player trust and fairness. A malicious or compromised owner can:

* Extend or reduce grace period based on who is king `(Game::updateGracePeriod())`.

* Increase/Decrease the feeIncreasePercentage right before a friend claims the throne `(Game::updateClaimFeeParameters())`.

* Increase platform fee after a big deposit to siphon more ETH `(Game::updatePlatformFeePercentage())`.

This undermines the core assumption of immutability and fairness in game mechanics.

***

## Proof of Concept (PoC)

This test verifies that the contract owner can update key game configuration parameters grace period, claim fee, fee increase percentage, and platform fee while the game is actively running (i.e., mid-game).

The test simulates a real game scenario:

* Player1 claims the throne, initiating the game

* The owner then changes game parameters

* Player2 claims the throne under the new conditions

* Assertions check that updated parameters are reflected

This test highlights a potential vulnerability:
These updates can be made during an active game, potentially giving unfair advantage or breaking assumptions for current or future participants.

```solidity
function test_updatingGracePeriodMidGameByOwner() public {
        // Player1 starts the game
        vm.startPrank(player1);
        game.claimThrone{value:game.claimFee()}();
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
        game.claimThrone{value:game.claimFee()}();
        assertEq(player2, game.currentKing());
        vm.stopPrank();
    }
```

***

## Recommended Mitigation:

Add a `Game::gameEndedOnly` modifier (or a similar check) to restrict such changes to only after the current game ends:

```solidity

function updateClaimFeeParameters(...) external onlyOwner gameEndedOnly { ... }

function updateGracePeriod(...) external onlyOwner gameEndedOnly { ... }

function updatePlatformFeePercentage(...) external onlyOwner gameEndedOnly { ... }

```

---

# [L-1] Incorrect `prizeAmount` Emitted in `Game::GameEnded` Event

## Root Cause

The `pot` variable is being reset to 0 **before** the `GameEnded` event is emitted.\
Since Solidity evaluates arguments at the time of `emit`, the value of `pot` passed to the event is `0`, even though the actual prize was transferred correctly.

***

## Vulnerable Function

```solidity
function declareWinner() external gameNotEnded {
    require(currentKing != address(0), "Game: No one has claimed the throne yet.");
    require(
        block.timestamp > lastClaimTime + gracePeriod,
        "Game: Grace period has not expired yet."
    );

    gameEnded = true;

    pendingWinnings[currentKing] = pendingWinnings[currentKing] + pot;
    pot = 0; // pot is reset before emitting

@>    emit GameEnded(currentKing, pot, block.timestamp, gameRound); // emits 0 always
}
```

***

## Impact

* **Incorrect event data**: The `GameEnded` event always emits `0` as the prize amount.

* **Off-chain consumers** (frontends, analytics, The Graph) will show misleading or wrong winner payouts.

* May break trust or external integrations relying on accurate event logs.

***

## Proof of Concept (PoC)

```solidity
event GameEnded(address indexed winner, uint256 prizeAmount, uint256 timestamp, uint256 round);

function test_GameEndedEmitsInCorrectPrizeAmount() public {
    // Arrange
    vm.startPrank(player1);
    game.claimThrone{value: game.claimFee()}(); // Assume this adds 1 ether to the pot

    vm.warp(block.timestamp + game.gracePeriod() + 1);

    // Expect the emit
    vm.expectEmit(true, false, false, false);
    emit GameEnded(game.currentKing(), game.pot(), block.timestamp, game.gameRound());

    // Act
    game.declareWinner();
}
```

***

## Recommended Mitigation:

Store the `pot` in a temporary variable **before** modifying it, and use that in both logic and event emission:

```solidity
function declareWinner() external gameNotEnded {
    require(currentKing != address(0), "Game: No one has claimed the throne yet.");
    require(
        block.timestamp > lastClaimTime + gracePeriod,
        "Game: Grace period has not expired yet."
    );

    gameEnded = true;

    uint256 prizeAmount = pot;

    pendingWinnings[currentKing] = pendingWinnings[currentKing] + prizeAmount;
    pot = 0;

    emit GameEnded(currentKing, prizeAmount, block.timestamp, gameRound); //correct value emitted
}
```

***

## Severity: Low

* It doesn't affect funds or security.

* But it does affect **off-chain trust**, **data accuracy**, and **external integrations**.

---

# [L-2] `Game::receive()` is empty and untracked

## Root Cause

The contract defines a `Game::receive()` function but leaves it empty, without emitting an event or implementing logic to handle incoming ETH. This means that any ETH sent directly to the contract (outside designated game functions) will be accepted silently, without any trace in the contract logs.

***

## Description

This allows the contract to accept plain ETH transfers (e.g., send(), transfer(), .call{value:}), but currently:

There is no event emitted to track who sent ETH and how much.

There is no logic in place to handle unexpected ETH transfers (e.g., refund or routing).

This can create confusion during auditing or operational monitoring, especially if someone mistakenly or maliciously sends ETH directly.

```Solidity
    receive() external payable {}
```

***

## Impact

* This can reduce transparency and create ambiguity during audits, monitoring, or debugging. If ETH is not meant to be sent directly, this may become an unintended ETH sink. Although it doesn’t break core game logic, it introduces unnecessary surface area and reduces visibility into user interactions.

***

## Proof of Concept (PoC)

This test simulates a scenario where a user (or bot) sends ETH directly to the contract using a low-level .call{value:}.

Since the `Game::receive()` function is present but empty, the ETH is accepted without any event emitted or state updated.

```Solidity
function test_SendingEthDirectToTheContract() public {
    // Arrange
    uint256 gameContractBalanceBefore = address(game).balance;

    // Act: maliciousActor sends ETH directly to the contract
    vm.startPrank(maliciousActor);
    (bool success, ) = address(game).call{value: 1 ether}("");
    require(success, "Tx Failed");

    uint256 gameContractBalanceAfter = address(game).balance;

    // Assert: Contract balance increased, proving ETH was accepted silently
    assertGt(gameContractBalanceAfter, gameContractBalanceBefore, "ETH was not received");
}
```

***

## Recommended Mitigation:

**Option-1:** If you want to track incoming ETH, emit an event:

```Solidity
event ETHReceived(address indexed sender, uint256 amount);

receive() external payable {
    emit ETHReceived(msg.sender, msg.value);
}
```

**Option-2:** If you want to restrict ETH, you can revert:

```Solidity
receive() external payable {
    revert("Direct ETH not allowed");
}
```

***

### Severity: Low

* Transparency: No way to know if ETH was sent directly unless node logs are inspected.

* Maintainability: Future developers/auditors may wonder why ETH was accepted but not handled.

* Security: Could be an unintended attack surface if ETH is not expected (e.g., griefing contract with dust ETH to bloat balance).

---

#

***Thanks for reading***

***Gakarot***

***Discord: _gakarot***

***Github: Netgakarot***

***Twitter/X: NetGakarot***

