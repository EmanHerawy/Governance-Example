// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../src/interfaces/IConvictionVoting.sol";
import "../src/mocks/MockConvictionVoting.sol";
import "../src/examples/VoteManager.sol";
import "../src/examples/DelegationManager.sol";
import "../src/examples/TallyAnalyzer.sol";
import "../src/examples/ConvictionCalculator.sol";

contract ConvictionVotingExamplesTest is Test {
    MockConvictionVoting public convictionVoting;
    VoteManager public voteManager;
    DelegationManager public delegationManager;
    TallyAnalyzer public tallyAnalyzer;
    ConvictionCalculator public calculator;

    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);

    uint16 public constant TRACK_ID = 0;
    uint32 public constant REF_INDEX = 1;

    function setUp() public {
        // Deploy mock and copy its code to the precompile address
        MockConvictionVoting mockImpl = new MockConvictionVoting();
        vm.etch(CONVICTION_VOTING_PRECOMPILE_ADDRESS, address(mockImpl).code);
        convictionVoting = MockConvictionVoting(CONVICTION_VOTING_PRECOMPILE_ADDRESS);

        voteManager = new VoteManager();
        delegationManager = new DelegationManager();
        tallyAnalyzer = new TallyAnalyzer();
        calculator = new ConvictionCalculator();

        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
        vm.label(charlie, "Charlie");
    }
    
    /* ========== VOTE MANAGER TESTS ========== */
    
    function test_VoteManager_GetVoteInfo() public {
        vm.prank(alice);
        convictionVoting.voteStandard(
            REF_INDEX,
            true,
            IConvictionVoting.Conviction.Locked2x,
            100 ether
        );
        
        VoteManager.VoteInfo memory info = voteManager.getVoteInfo(alice, TRACK_ID, REF_INDEX);
        
        assertTrue(info.exists);
        assertEq(info.voteTypeString, "Standard");
        assertEq(info.convictionString, "Locked2x");
        assertEq(info.totalAmount, 100 ether);
        assertTrue(info.isAye);
    }
    
    function test_VoteManager_GetVoteInfo_Split() public {
        vm.prank(alice);
        convictionVoting.voteSplit(REF_INDEX, 60 ether, 40 ether);
        
        VoteManager.VoteInfo memory info = voteManager.getVoteInfo(alice, TRACK_ID, REF_INDEX);
        
        assertTrue(info.exists);
        assertEq(info.voteTypeString, "Split");
        assertEq(info.totalAmount, 100 ether);
    }
    
    function test_VoteManager_BatchVote() public {
        uint32[] memory indices = new uint32[](3);
        indices[0] = 1;
        indices[1] = 2;
        indices[2] = 3;
        
        // Alice calls batchVoteStandard directly
        vm.prank(alice);
        uint256 successCount = voteManager.batchVoteStandard(
            indices,
            true,
            IConvictionVoting.Conviction.Locked1x,
            50 ether
        );
        
        assertEq(successCount, 3);
        
        // Verify all votes - they should be from voteManager address, not alice
        for (uint256 i = 0; i < 3; i++) {
            (bool exists, , , , , , ) = convictionVoting.getVoting(address(voteManager), TRACK_ID, indices[i]);
            assertTrue(exists);
        }
    }
    
    function test_VoteManager_BatchRemoveVotes() public {
        // First vote on multiple referendums using voteManager
        uint32[] memory indices = new uint32[](3);
        indices[0] = 1;
        indices[1] = 2;
        indices[2] = 3;
        
        vm.startPrank(alice);
        voteManager.batchVoteStandard(
            indices,
            true,
            IConvictionVoting.Conviction.Locked1x,
            50 ether
        );
        
        // Remove all votes
        uint256 successCount = voteManager.batchRemoveVotes(TRACK_ID, indices);
        vm.stopPrank();
        
        assertEq(successCount, 3);
        
        // Verify all removed
        for (uint256 i = 0; i < 3; i++) {
            (bool exists, , , , , , ) = convictionVoting.getVoting(address(voteManager), TRACK_ID, indices[i]);
            assertFalse(exists);
        }
    }
    
    function test_VoteManager_HasVotedOnAny() public {
        uint32[] memory indices = new uint32[](3);
        indices[0] = 1;
        indices[1] = 2;
        indices[2] = 3;
        
        // Initially no votes
        (bool hasVoted, ) = voteManager.hasVotedOnAny(alice, TRACK_ID, indices);
        assertFalse(hasVoted);
        
        // Vote on second referendum directly
        vm.prank(alice);
        convictionVoting.voteStandard(indices[1], true, IConvictionVoting.Conviction.Locked1x, 50 ether);
        
        (bool hasVotedAfter, uint32 firstIndex) = voteManager.hasVotedOnAny(alice, TRACK_ID, indices);
        assertTrue(hasVotedAfter);
        assertEq(firstIndex, indices[1]);
    }
    
    function test_VoteManager_GetTotalVotingPower() public {
        uint32[] memory indices = new uint32[](3);
        indices[0] = 1;
        indices[1] = 2;
        indices[2] = 3;
        
        vm.startPrank(alice);
        convictionVoting.voteStandard(indices[0], true, IConvictionVoting.Conviction.Locked1x, 100 ether);
        convictionVoting.voteSplit(indices[1], 60 ether, 40 ether);
        convictionVoting.voteStandard(indices[2], false, IConvictionVoting.Conviction.Locked2x, 80 ether);
        vm.stopPrank();
        
        (uint128 totalPower, uint256 voteCount) = voteManager.getTotalVotingPower(alice, TRACK_ID, indices);
        
        assertEq(voteCount, 3);
        assertEq(totalPower, 100 ether + 100 ether + 80 ether);
    }
    
    /* ========== DELEGATION MANAGER TESTS ========== */
    
    function test_DelegationManager_GetDelegationInfo() public {
        vm.prank(alice);
        convictionVoting.delegate(TRACK_ID, bob, IConvictionVoting.Conviction.Locked3x, 100 ether);
        
        DelegationManager.DelegationInfo memory info = 
            delegationManager.getDelegationInfo(alice, TRACK_ID);
        
        assertTrue(info.isDelegating);
        assertEq(info.target, bob);
        assertEq(info.balance, 100 ether);
        assertEq(info.convictionString, "Locked3x");
        assertEq(info.effectiveVotingPower, 300 ether);
    }
    
    function test_DelegationManager_BatchDelegate() public {
        uint16[] memory trackIds = new uint16[](3);
        trackIds[0] = 0;
        trackIds[1] = 1;
        trackIds[2] = 2;
        
        address[] memory targets = new address[](3);
        targets[0] = bob;
        targets[1] = charlie;
        targets[2] = bob;
        
        IConvictionVoting.Conviction[] memory convictions = new IConvictionVoting.Conviction[](3);
        convictions[0] = IConvictionVoting.Conviction.Locked1x;
        convictions[1] = IConvictionVoting.Conviction.Locked2x;
        convictions[2] = IConvictionVoting.Conviction.Locked3x;
        
        uint128[] memory balances = new uint128[](3);
        balances[0] = 50 ether;
        balances[1] = 60 ether;
        balances[2] = 70 ether;
        
        vm.prank(alice);
        delegationManager.batchDelegate(trackIds, targets, convictions, balances);
        
        // Verify all delegations - they're from delegationManager, not alice
        for (uint256 i = 0; i < 3; i++) {
            (address target, , ) = convictionVoting.getDelegation(address(delegationManager), trackIds[i]);
            assertEq(target, targets[i]);
        }
    }
    
    function test_DelegationManager_BatchUndelegate() public {
        uint16[] memory trackIds = new uint16[](2);
        trackIds[0] = 0;
        trackIds[1] = 1;
        
        // First delegate using delegationManager
        vm.startPrank(alice);
        
        address[] memory targets = new address[](2);
        targets[0] = bob;
        targets[1] = charlie;
        
        IConvictionVoting.Conviction[] memory convictions = new IConvictionVoting.Conviction[](2);
        convictions[0] = IConvictionVoting.Conviction.Locked1x;
        convictions[1] = IConvictionVoting.Conviction.Locked2x;
        
        uint128[] memory balances = new uint128[](2);
        balances[0] = 50 ether;
        balances[1] = 60 ether;
        
        delegationManager.batchDelegate(trackIds, targets, convictions, balances);
        
        // Then undelegate all
        delegationManager.batchUndelegate(trackIds);
        vm.stopPrank();
        
        // Verify all undelegated
        for (uint256 i = 0; i < 2; i++) {
            (address target, , ) = convictionVoting.getDelegation(address(delegationManager), trackIds[i]);
            assertEq(target, address(0));
        }
    }
    
    function test_DelegationManager_Redelegate() public {
        // Initial delegation to Bob using delegationManager
        vm.startPrank(alice);
        
        uint16[] memory trackIds = new uint16[](1);
        trackIds[0] = TRACK_ID;
        address[] memory targets = new address[](1);
        targets[0] = bob;
        IConvictionVoting.Conviction[] memory convictions = new IConvictionVoting.Conviction[](1);
        convictions[0] = IConvictionVoting.Conviction.Locked1x;
        uint128[] memory balances = new uint128[](1);
        balances[0] = 50 ether;
        
        delegationManager.batchDelegate(trackIds, targets, convictions, balances);
        
        (address targetBefore, , ) = convictionVoting.getDelegation(address(delegationManager), TRACK_ID);
        assertEq(targetBefore, bob);
        
        // Redelegate to Charlie
        delegationManager.redelegate(TRACK_ID, charlie, IConvictionVoting.Conviction.Locked2x, 75 ether);
        vm.stopPrank();
        
        (address targetAfter, uint128 balanceAfter, IConvictionVoting.Conviction convictionAfter) = 
            convictionVoting.getDelegation(address(delegationManager), TRACK_ID);
        
        assertEq(targetAfter, charlie);
        assertEq(balanceAfter, 75 ether);
        assertEq(uint8(convictionAfter), uint8(IConvictionVoting.Conviction.Locked2x));
    }
    
    /* ========== TALLY ANALYZER TESTS ========== */
    
    function test_TallyAnalyzer_AnalyzeTally() public {
        convictionVoting._setTally(REF_INDEX, 750 ether, 250 ether, 900 ether);
        
        TallyAnalyzer.TallyAnalysis memory analysis = 
            tallyAnalyzer.analyzeTally(REF_INDEX, 10000 ether);
        
        assertTrue(analysis.exists);
        assertEq(analysis.ayes, 750 ether);
        assertEq(analysis.nays, 250 ether);
        assertEq(analysis.support, 900 ether);
        assertEq(analysis.totalVotes, 1000 ether);
        assertEq(analysis.approvalPercentage, 75);
        assertEq(analysis.participationScore, 9);
        assertEq(analysis.outcome, "Strong Approval");
    }
    
    function test_TallyAnalyzer_CompareTallies() public {
        uint32[] memory indices = new uint32[](3);
        indices[0] = 1;
        indices[1] = 2;
        indices[2] = 3;
        
        convictionVoting._setTally(indices[0], 1000 ether, 500 ether, 900 ether);
        convictionVoting._setTally(indices[1], 800 ether, 700 ether, 1200 ether);
        convictionVoting._setTally(indices[2], 600 ether, 400 ether, 950 ether);
        
        (uint32 mostAyes, uint32 mostNays, uint32 mostSupport, uint32 mostContested) = 
            tallyAnalyzer.compareTallies(indices);
        
        assertEq(mostAyes, indices[0]);
        assertEq(mostNays, indices[1]);
        assertEq(mostSupport, indices[1]);
        assertEq(mostContested, indices[1]); // 800 - 700 = 100 (smallest difference)
    }
    
    function test_TallyAnalyzer_GetAggregateStats() public {
        uint32[] memory indices = new uint32[](3);
        indices[0] = 1;
        indices[1] = 2;
        indices[2] = 3;
        
        convictionVoting._setTally(indices[0], 100 ether, 50 ether, 90 ether);
        convictionVoting._setTally(indices[1], 200 ether, 100 ether, 180 ether);
        convictionVoting._setTally(indices[2], 300 ether, 150 ether, 270 ether);
        
        (
            uint256 totalReferendums,
            uint128 totalAyes,
            uint128 totalNays,
            uint128 totalSupport,
            uint128 avgAyes,
            uint128 avgNays
        ) = tallyAnalyzer.getAggregateStats(indices);
        
        assertEq(totalReferendums, 3);
        assertEq(totalAyes, 600 ether);
        assertEq(totalNays, 300 ether);
        assertEq(totalSupport, 540 ether);
        assertEq(avgAyes, 200 ether);
        assertEq(avgNays, 100 ether);
    }
    
    function test_TallyAnalyzer_MeetsQuorum() public {
        convictionVoting._setTally(REF_INDEX, 750 ether, 250 ether, 900 ether);
        
        (bool meets, uint128 required, uint128 actual) = 
            tallyAnalyzer.meetsQuorum(REF_INDEX, 10000 ether, 5);
        
        assertTrue(meets);
        assertEq(required, 500 ether); // 5% of 10000
        assertEq(actual, 900 ether);
    }
    
    /* ========== CONVICTION CALCULATOR TESTS ========== */
    
    function test_ConvictionCalculator_CalculateVotingPower() public {
        uint128 balance = 100 ether;
        
        assertEq(calculator.calculateVotingPower(balance, IConvictionVoting.Conviction.None), 10 ether);
        assertEq(calculator.calculateVotingPower(balance, IConvictionVoting.Conviction.Locked1x), 100 ether);
        assertEq(calculator.calculateVotingPower(balance, IConvictionVoting.Conviction.Locked2x), 200 ether);
        assertEq(calculator.calculateVotingPower(balance, IConvictionVoting.Conviction.Locked3x), 300 ether);
        assertEq(calculator.calculateVotingPower(balance, IConvictionVoting.Conviction.Locked4x), 400 ether);
        assertEq(calculator.calculateVotingPower(balance, IConvictionVoting.Conviction.Locked5x), 500 ether);
        assertEq(calculator.calculateVotingPower(balance, IConvictionVoting.Conviction.Locked6x), 600 ether);
    }
    
    function test_ConvictionCalculator_GetLockPeriods() public {
        assertEq(calculator.getLockPeriods(IConvictionVoting.Conviction.None), 0);
        assertEq(calculator.getLockPeriods(IConvictionVoting.Conviction.Locked1x), 1);
        assertEq(calculator.getLockPeriods(IConvictionVoting.Conviction.Locked2x), 2);
        assertEq(calculator.getLockPeriods(IConvictionVoting.Conviction.Locked3x), 4);
        assertEq(calculator.getLockPeriods(IConvictionVoting.Conviction.Locked4x), 8);
        assertEq(calculator.getLockPeriods(IConvictionVoting.Conviction.Locked5x), 16);
        assertEq(calculator.getLockPeriods(IConvictionVoting.Conviction.Locked6x), 32);
    }
    
    function test_ConvictionCalculator_GetAllConvictionOptions() public {
        ConvictionCalculator.ConvictionDetails[7] memory options = 
            calculator.getAllConvictionOptions(100 ether);
        
        assertEq(options.length, 7);
        assertEq(options[0].name, "None");
        assertEq(options[0].votingPower, 10 ether);
        assertEq(options[0].lockPeriods, 0);
        
        assertEq(options[6].name, "Locked6x");
        assertEq(options[6].votingPower, 600 ether);
        assertEq(options[6].lockPeriods, 32);
    }
    
    function test_ConvictionCalculator_FindOptimalConviction() public {
        (
            IConvictionVoting.Conviction optimal,
            uint128 actualPower,
            bool exactMatch
        ) = calculator.findOptimalConviction(100 ether, 200 ether);
        
        assertEq(uint8(optimal), uint8(IConvictionVoting.Conviction.Locked2x));
        assertEq(actualPower, 200 ether);
        assertTrue(exactMatch);
    }
    
    function test_ConvictionCalculator_CompareConvictionEfficiency() public {
        (
            uint128 power1,
            uint128 power2,
            uint256 lockPeriods1,
            uint256 lockPeriods2,
            string memory recommendation
        ) = calculator.compareConvictionEfficiency(
            100 ether,
            IConvictionVoting.Conviction.Locked2x,
            IConvictionVoting.Conviction.Locked3x
        );
        
        assertEq(power1, 200 ether);
        assertEq(power2, 300 ether);
        assertEq(lockPeriods1, 2);
        assertEq(lockPeriods2, 4);
    }
    
    /* ========== INTEGRATION TESTS ========== */
    
    function test_FullVotingWorkflow() public {
        // 1. Alice analyzes conviction options
        ConvictionCalculator.ConvictionDetails[7] memory options = 
            calculator.getAllConvictionOptions(100 ether);
        
        // 2. Alice chooses Locked4x and votes directly
        vm.prank(alice);
        convictionVoting.voteStandard(
            REF_INDEX,
            true,
            options[4].level,
            100 ether
        );
        
        // 3. Check vote info
        VoteManager.VoteInfo memory voteInfo = voteManager.getVoteInfo(alice, TRACK_ID, REF_INDEX);
        assertTrue(voteInfo.exists);
        assertEq(voteInfo.convictionString, "Locked4x");
        
        // 4. Bob delegates to Alice directly
        vm.prank(bob);
        convictionVoting.delegate(TRACK_ID, alice, IConvictionVoting.Conviction.Locked2x, 80 ether);
        
        // 5. Check delegation
        DelegationManager.DelegationInfo memory delegationInfo = 
            delegationManager.getDelegationInfo(bob, TRACK_ID);
        
        assertTrue(delegationInfo.isDelegating);
        assertEq(delegationInfo.target, alice);
    }
}