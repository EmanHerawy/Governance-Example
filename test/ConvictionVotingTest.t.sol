// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../src/interfaces/IConvictionVoting.sol";
import "../src/mocks/MockConvictionVoting.sol";

contract ConvictionVotingTest is Test {
    MockConvictionVoting public convictionVoting;
    
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);
    
    uint16 public constant TRACK_ID = 0;
    uint32 public constant REF_INDEX = 1;
    uint128 public constant VOTE_AMOUNT = 100 ether;
    
    event VoteCast(address indexed voter, uint32 indexed referendumIndex, IConvictionVoting.VotingType votingType);
    event Delegated(address indexed delegator, uint16 indexed trackId, address indexed target);
    
    function setUp() public {
        convictionVoting = new MockConvictionVoting();
        
        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
        vm.label(charlie, "Charlie");
    }
    
    /* ========== STANDARD VOTE TESTS ========== */
    
    function test_VoteStandard_Aye() public {
        vm.startPrank(alice);
        
        vm.expectEmit(true, true, false, true);
        emit VoteCast(alice, REF_INDEX, IConvictionVoting.VotingType.Standard);
        
        convictionVoting.voteStandard(
            REF_INDEX,
            true,
            IConvictionVoting.Conviction.Locked1x,
            VOTE_AMOUNT
        );
        
        (
            bool exists,
            IConvictionVoting.VotingType votingType,
            bool aye,
            uint128 ayeAmount,
            uint128 nayAmount,
            uint128 abstainAmount,
            IConvictionVoting.Conviction conviction
        ) = convictionVoting.getVoting(alice, TRACK_ID, REF_INDEX);
        
        assertTrue(exists);
        assertEq(uint8(votingType), uint8(IConvictionVoting.VotingType.Standard));
        assertTrue(aye);
        assertEq(ayeAmount, VOTE_AMOUNT);
        assertEq(nayAmount, 0);
        assertEq(abstainAmount, 0);
        assertEq(uint8(conviction), uint8(IConvictionVoting.Conviction.Locked1x));
        
        vm.stopPrank();
    }
    
    function test_VoteStandard_Nay() public {
        vm.startPrank(alice);
        
        convictionVoting.voteStandard(
            REF_INDEX,
            false,
            IConvictionVoting.Conviction.Locked2x,
            VOTE_AMOUNT
        );
        
        (
            bool exists,
            IConvictionVoting.VotingType votingType,
            bool aye,
            uint128 ayeAmount,
            uint128 nayAmount,
            ,
            IConvictionVoting.Conviction conviction
        ) = convictionVoting.getVoting(alice, TRACK_ID, REF_INDEX);
        
        assertTrue(exists);
        assertEq(uint8(votingType), uint8(IConvictionVoting.VotingType.Standard));
        assertFalse(aye);
        assertEq(ayeAmount, 0);
        assertEq(nayAmount, VOTE_AMOUNT);
        assertEq(uint8(conviction), uint8(IConvictionVoting.Conviction.Locked2x));
        
        vm.stopPrank();
    }
    
    function test_VoteStandard_AllConvictions() public {
        IConvictionVoting.Conviction[7] memory convictions = [
            IConvictionVoting.Conviction.None,
            IConvictionVoting.Conviction.Locked1x,
            IConvictionVoting.Conviction.Locked2x,
            IConvictionVoting.Conviction.Locked3x,
            IConvictionVoting.Conviction.Locked4x,
            IConvictionVoting.Conviction.Locked5x,
            IConvictionVoting.Conviction.Locked6x
        ];
        
        vm.startPrank(alice);
        
        for (uint256 i = 0; i < convictions.length; i++) {
            uint32 refIndex = uint32(i);
            convictionVoting.voteStandard(refIndex, true, convictions[i], VOTE_AMOUNT);
            
            (, , , , , , IConvictionVoting.Conviction conviction) = 
                convictionVoting.getVoting(alice, TRACK_ID, refIndex);
            
            assertEq(uint8(conviction), uint8(convictions[i]));
        }
        
        vm.stopPrank();
    }
    
    function test_VoteStandard_RevertZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("InvalidVoteAmount()"));
        convictionVoting.voteStandard(REF_INDEX, true, IConvictionVoting.Conviction.Locked1x, 0);
    }
    
    /* ========== SPLIT VOTE TESTS ========== */
    
    function test_VoteSplit() public {
        vm.startPrank(alice);
        
        uint128 ayeAmount = 60 ether;
        uint128 nayAmount = 40 ether;
        
        vm.expectEmit(true, true, false, true);
        emit VoteCast(alice, REF_INDEX, IConvictionVoting.VotingType.Split);
        
        convictionVoting.voteSplit(REF_INDEX, ayeAmount, nayAmount);
        
        (
            bool exists,
            IConvictionVoting.VotingType votingType,
            ,
            uint128 actualAye,
            uint128 actualNay,
            uint128 abstainAmount,
            IConvictionVoting.Conviction conviction
        ) = convictionVoting.getVoting(alice, TRACK_ID, REF_INDEX);
        
        assertTrue(exists);
        assertEq(uint8(votingType), uint8(IConvictionVoting.VotingType.Split));
        assertEq(actualAye, ayeAmount);
        assertEq(actualNay, nayAmount);
        assertEq(abstainAmount, 0);
        assertEq(uint8(conviction), uint8(IConvictionVoting.Conviction.None));
        
        vm.stopPrank();
    }
    
    function test_VoteSplit_AyeOnly() public {
        vm.prank(alice);
        convictionVoting.voteSplit(REF_INDEX, 100 ether, 0);
        
        (, , , uint128 ayeAmount, uint128 nayAmount, , ) = 
            convictionVoting.getVoting(alice, TRACK_ID, REF_INDEX);
        
        assertEq(ayeAmount, 100 ether);
        assertEq(nayAmount, 0);
    }
    
    function test_VoteSplit_RevertBothZero() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("InvalidVoteAmount()"));
        convictionVoting.voteSplit(REF_INDEX, 0, 0);
    }
    
    /* ========== SPLIT ABSTAIN TESTS ========== */
    
    function test_VoteSplitAbstain() public {
        vm.startPrank(alice);
        
        uint128 ayeAmount = 40 ether;
        uint128 nayAmount = 30 ether;
        uint128 abstainAmount = 30 ether;
        
        convictionVoting.voteSplitAbstain(REF_INDEX, ayeAmount, nayAmount, abstainAmount);
        
        (
            bool exists,
            IConvictionVoting.VotingType votingType,
            ,
            uint128 actualAye,
            uint128 actualNay,
            uint128 actualAbstain,
            
        ) = convictionVoting.getVoting(alice, TRACK_ID, REF_INDEX);
        
        assertTrue(exists);
        assertEq(uint8(votingType), uint8(IConvictionVoting.VotingType.SplitAbstain));
        assertEq(actualAye, ayeAmount);
        assertEq(actualNay, nayAmount);
        assertEq(actualAbstain, abstainAmount);
        
        vm.stopPrank();
    }
    
    /* ========== REMOVE VOTE TESTS ========== */
    
    function test_RemoveVote() public {
        vm.startPrank(alice);
        
        convictionVoting.voteStandard(REF_INDEX, true, IConvictionVoting.Conviction.Locked1x, VOTE_AMOUNT);
        
        (bool existsBefore, , , , , , ) = convictionVoting.getVoting(alice, TRACK_ID, REF_INDEX);
        assertTrue(existsBefore);
        
        convictionVoting.removeVote(TRACK_ID, REF_INDEX);
        
        (bool existsAfter, , , , , , ) = convictionVoting.getVoting(alice, TRACK_ID, REF_INDEX);
        assertFalse(existsAfter);
        
        vm.stopPrank();
    }
    
    function test_RemoveVote_RevertIfNotExists() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("VoteNotFound(address,uint16,uint32)", alice, TRACK_ID, REF_INDEX));
        convictionVoting.removeVote(TRACK_ID, REF_INDEX);
    }
    
    /* ========== DELEGATION TESTS ========== */
    
    function test_Delegate() public {
        vm.startPrank(alice);
        
        vm.expectEmit(true, true, true, true);
        emit Delegated(alice, TRACK_ID, bob);
        
        convictionVoting.delegate(TRACK_ID, bob, IConvictionVoting.Conviction.Locked3x, VOTE_AMOUNT);
        
        (address target, uint128 balance, IConvictionVoting.Conviction conviction) = 
            convictionVoting.getDelegation(alice, TRACK_ID);
        
        assertEq(target, bob);
        assertEq(balance, VOTE_AMOUNT);
        assertEq(uint8(conviction), uint8(IConvictionVoting.Conviction.Locked3x));
        
        vm.stopPrank();
    }
    
    function test_Undelegate() public {
        vm.startPrank(alice);
        
        convictionVoting.delegate(TRACK_ID, bob, IConvictionVoting.Conviction.Locked1x, VOTE_AMOUNT);
        
        (address targetBefore, , ) = convictionVoting.getDelegation(alice, TRACK_ID);
        assertEq(targetBefore, bob);
        
        convictionVoting.undelegate(TRACK_ID);
        
        (address targetAfter, uint128 balanceAfter, ) = convictionVoting.getDelegation(alice, TRACK_ID);
        assertEq(targetAfter, address(0));
        assertEq(balanceAfter, 0);
        
        vm.stopPrank();
    }
    
    function test_Delegate_RevertZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("InvalidVoteAmount()"));
        convictionVoting.delegate(TRACK_ID, bob, IConvictionVoting.Conviction.Locked1x, 0);
    }
    
    /* ========== UNLOCK TESTS ========== */
    
    function test_Unlock_Self() public {
        vm.prank(alice);
        convictionVoting.unlock(TRACK_ID, alice);
    }
    
    function test_Unlock_Others() public {
        vm.prank(alice);
        convictionVoting.unlock(TRACK_ID, bob);
    }
    
    /* ========== TALLY TESTS ========== */
    
    function test_GetReferendumTally() public {
        // Setup tally
        convictionVoting._setTally(REF_INDEX, 1000 ether, 500 ether, 900 ether);
        
        (bool exists, uint128 ayes, uint128 nays, uint128 support) = 
            convictionVoting.getReferendumTally(REF_INDEX);
        
        assertTrue(exists);
        assertEq(ayes, 1000 ether);
        assertEq(nays, 500 ether);
        assertEq(support, 900 ether);
    }
    
    function test_GetReferendumTally_NonExistent() public {
        (bool exists, , , ) = convictionVoting.getReferendumTally(999);
        assertFalse(exists);
    }
    
    /* ========== INTEGRATION TESTS ========== */
    
    function test_MultipleVoters() public {
        // Alice votes aye
        vm.prank(alice);
        convictionVoting.voteStandard(REF_INDEX, true, IConvictionVoting.Conviction.Locked2x, 100 ether);
        
        // Bob votes nay
        vm.prank(bob);
        convictionVoting.voteStandard(REF_INDEX, false, IConvictionVoting.Conviction.Locked1x, 50 ether);
        
        // Charlie splits
        vm.prank(charlie);
        convictionVoting.voteSplit(REF_INDEX, 30 ether, 20 ether);
        
        // Verify all votes exist
        (bool aliceExists, , , , , , ) = convictionVoting.getVoting(alice, TRACK_ID, REF_INDEX);
        (bool bobExists, , , , , , ) = convictionVoting.getVoting(bob, TRACK_ID, REF_INDEX);
        (bool charlieExists, , , , , , ) = convictionVoting.getVoting(charlie, TRACK_ID, REF_INDEX);
        
        assertTrue(aliceExists);
        assertTrue(bobExists);
        assertTrue(charlieExists);
    }
    
    function test_ChangeVote() public {
        vm.startPrank(alice);
        
        // Initial vote
        convictionVoting.voteStandard(REF_INDEX, true, IConvictionVoting.Conviction.Locked1x, 100 ether);
        
        (, , bool ayeBefore, , , , ) = convictionVoting.getVoting(alice, TRACK_ID, REF_INDEX);
        assertTrue(ayeBefore);
        
        // Change to nay (overwrite)
        convictionVoting.voteStandard(REF_INDEX, false, IConvictionVoting.Conviction.Locked2x, 150 ether);
        
        (, , bool ayeAfter, uint128 ayeAmount, uint128 nayAmount, , IConvictionVoting.Conviction conviction) = 
            convictionVoting.getVoting(alice, TRACK_ID, REF_INDEX);
        
        assertFalse(ayeAfter);
        assertEq(ayeAmount, 0);
        assertEq(nayAmount, 150 ether);
        assertEq(uint8(conviction), uint8(IConvictionVoting.Conviction.Locked2x));
        
        vm.stopPrank();
    }
    
    /* ========== FUZZ TESTS ========== */
    
    function testFuzz_VoteStandard(bool aye, uint8 convictionRaw, uint128 balance) public {
        vm.assume(balance > 0 && balance < type(uint128).max / 10);
        vm.assume(convictionRaw <= 6);
        
        IConvictionVoting.Conviction conviction = IConvictionVoting.Conviction(convictionRaw);
        
        vm.prank(alice);
        convictionVoting.voteStandard(REF_INDEX, aye, conviction, balance);
        
        (bool exists, , bool actualAye, , , , IConvictionVoting.Conviction actualConviction) = 
            convictionVoting.getVoting(alice, TRACK_ID, REF_INDEX);
        
        assertTrue(exists);
        assertEq(actualAye, aye);
        assertEq(uint8(actualConviction), convictionRaw);
    }
    
    function testFuzz_VoteSplit(uint128 ayeAmount, uint128 nayAmount) public {
        vm.assume(ayeAmount > 0 || nayAmount > 0);
        vm.assume(ayeAmount < type(uint128).max / 2);
        vm.assume(nayAmount < type(uint128).max / 2);
        
        vm.prank(alice);
        convictionVoting.voteSplit(REF_INDEX, ayeAmount, nayAmount);
        
        (bool exists, IConvictionVoting.VotingType votingType, , uint128 actualAye, uint128 actualNay, , ) = 
            convictionVoting.getVoting(alice, TRACK_ID, REF_INDEX);
        
        assertTrue(exists);
        assertEq(uint8(votingType), uint8(IConvictionVoting.VotingType.Split));
        assertEq(actualAye, ayeAmount);
        assertEq(actualNay, nayAmount);
    }
    
    /* ========== GAS BENCHMARKS ========== */
    
    function testGas_VoteStandard() public {
        vm.prank(alice);
        convictionVoting.voteStandard(REF_INDEX, true, IConvictionVoting.Conviction.Locked1x, VOTE_AMOUNT);
    }
    
    function testGas_VoteSplit() public {
        vm.prank(alice);
        convictionVoting.voteSplit(REF_INDEX, 60 ether, 40 ether);
    }
    
    function testGas_Delegate() public {
        vm.prank(alice);
        convictionVoting.delegate(TRACK_ID, bob, IConvictionVoting.Conviction.Locked3x, VOTE_AMOUNT);
    }
    
    function testGas_GetVoting() public view {
        convictionVoting.getVoting(alice, TRACK_ID, REF_INDEX);
    }
}