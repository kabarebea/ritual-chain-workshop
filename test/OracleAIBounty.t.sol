// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "forge-std/Test.sol";
import "../src/OracleAIBounty.sol";

contract OracleAIBountyTest is Test {
    OracleAIBounty public bounty;
    address owner = address(0x1);
    address alice = address(0x2);
    address bob = address(0x3);
    address oracle1 = address(0x4);
    address oracle2 = address(0x5);
    address oracle3 = address(0x6);
    uint256 challengeId;
    bytes32 aliceCommitment;
    bytes32 bobCommitment;
    bytes32 aliceSalt = keccak256("alice_salt");
    bytes32 bobSalt = keccak256("bob_salt");
    string aliceAnswer = "Alice's solution";
    string bobAnswer = "Bob's solution";
    uint256 reward = 1 ether;
    uint256 oracleStake = 0.1 ether;

    function setUp() public {
        vm.deal(owner, 10 ether);
        vm.deal(alice, 1 ether);
        vm.deal(bob, 1 ether);
        vm.deal(oracle1, 1 ether);
        vm.deal(oracle2, 1 ether);
        vm.deal(oracle3, 1 ether);
        bounty = new OracleAIBounty();
        vm.startPrank(owner);
        uint256 commitDeadline = block.timestamp + 1 days;
        bounty.createChallenge{value: reward}("Test", commitDeadline, 2 days, 3 days);
        challengeId = 0;
        vm.stopPrank();
        aliceCommitment = keccak256(abi.encodePacked(aliceAnswer, aliceSalt, alice, challengeId));
        bobCommitment = keccak256(abi.encodePacked(bobAnswer, bobSalt, bob, challengeId));
    }

    function testFullFlow() public {
        vm.startPrank(alice);
        bounty.submitCommitment(challengeId, aliceCommitment);
        vm.stopPrank();

        vm.startPrank(bob);
        bounty.submitCommitment(challengeId, bobCommitment);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days + 1);

        vm.startPrank(alice);
        bounty.revealAnswer(challengeId, aliceAnswer, aliceSalt);
        vm.stopPrank();

        vm.startPrank(bob);
        bounty.revealAnswer(challengeId, bobAnswer, bobSalt);
        vm.stopPrank();

        vm.startPrank(oracle1);
        bounty.addOracle{value: oracleStake}(challengeId);
        vm.stopPrank();

        vm.startPrank(oracle2);
        bounty.addOracle{value: oracleStake}(challengeId);
        vm.stopPrank();

        vm.startPrank(oracle3);
        bounty.addOracle{value: oracleStake}(challengeId);
        vm.stopPrank();

        vm.warp(block.timestamp + 2 days + 1);

        vm.startPrank(oracle1);
        bounty.voteOracle(challengeId, bob);
        vm.stopPrank();

        vm.startPrank(oracle2);
        bounty.voteOracle(challengeId, bob);
        vm.stopPrank();

        vm.startPrank(oracle3);
        bounty.voteOracle(challengeId, alice);
        vm.stopPrank();

        vm.warp(block.timestamp + 3 days + 1);

        vm.startPrank(owner);
        bounty.finalizeWinner(challengeId);
        vm.stopPrank();

        OracleAIBounty.ChallengeInfo memory info = bounty.getChallengeInfo(challengeId);
        assertTrue(info.finalized);
        assertEq(info.winner, bob);
        assertEq(bob.balance, 1 ether + reward);
    }

    function testCannotRevealBeforeDeadline() public {
        vm.startPrank(alice);
        bounty.submitCommitment(challengeId, aliceCommitment);
        vm.expectRevert("Not reveal phase");
        bounty.revealAnswer(challengeId, aliceAnswer, aliceSalt);
        vm.stopPrank();
    }

    function testOnlyOracleCanVote() public {
        vm.startPrank(alice);
        bounty.submitCommitment(challengeId, aliceCommitment);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days + 1);
        vm.startPrank(alice);
        bounty.revealAnswer(challengeId, aliceAnswer, aliceSalt);
        vm.stopPrank();

        vm.startPrank(oracle1);
        bounty.addOracle{value: oracleStake}(challengeId);
        vm.stopPrank();

        vm.warp(block.timestamp + 2 days + 1);
        vm.startPrank(alice);
        vm.expectRevert("Not an oracle for this challenge");
        bounty.voteOracle(challengeId, alice);
        vm.stopPrank();
    }

    function testCannotFinalizeWithoutVotes() public {
        vm.startPrank(alice);
        bounty.submitCommitment(challengeId, aliceCommitment);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days + 1);
        vm.startPrank(alice);
        bounty.revealAnswer(challengeId, aliceAnswer, aliceSalt);
        vm.stopPrank();

        vm.startPrank(oracle1);
        bounty.addOracle{value: oracleStake}(challengeId);
        vm.stopPrank();

        // Warp to after oracle deadline: 1 day commit + 2 days reveal + 3 days oracle = 6 days
        vm.warp(block.timestamp + 6 days + 1);
        vm.startPrank(owner);
        vm.expectRevert("No oracle votes");
        bounty.finalizeWinner(challengeId);
        vm.stopPrank();
    }

    function testOracleStakeRequired() public {
        vm.warp(block.timestamp + 1 days + 1);
        vm.startPrank(oracle1);
        vm.expectRevert("Stake too low");
        bounty.addOracle{value: oracleStake - 1 wei}(challengeId);
        vm.stopPrank();
    }
}
