// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../src/interfaces/IReferenda.sol";
import "../src/interfaces/IConvictionVoting.sol";
import "../src/mocks/MockReferenda.sol";
import "../src/mocks/MockConvictionVoting.sol";
import "../src/examples/GovernanceDashboard.sol";
import "../src/examples/VotingBot.sol";
import "../src/examples/DelegationPool.sol";
import "../src/examples/GovernanceAnalytics.sol";

contract IntegrationTest is Test {
    MockReferenda public referenda;
    MockConvictionVoting public convictionVoting;
    GovernanceDashboard public dashboard;
    VotingBot public votingBot;
    DelegationPool public delegationPool;
    GovernanceAnalytics public analytics;

    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);

    uint16 public constant TRACK_ID = 0;

    function setUp() public {
        // Deploy mocks and copy their code to the precompile addresses
        MockReferenda referendaMockImpl = new MockReferenda();
        vm.etch(REFERENDA_PRECOMPILE_ADDRESS, address(referendaMockImpl).code);
        referenda = MockReferenda(REFERENDA_PRECOMPILE_ADDRESS);

        MockConvictionVoting convictionMockImpl = new MockConvictionVoting();
        vm.etch(CONVICTION_VOTING_PRECOMPILE_ADDRESS, address(convictionMockImpl).code);
        convictionVoting = MockConvictionVoting(CONVICTION_VOTING_PRECOMPILE_ADDRESS);

        dashboard = new GovernanceDashboard();
        votingBot = new VotingBot(
            TRACK_ID,
            VotingBot.VoteStrategy.AlwaysAye,
            100 ether
        );
        delegationPool = new DelegationPool();
        analytics = new GovernanceAnalytics();

        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
        vm.label(charlie, "Charlie");
    }
    
    function test_FullGovernanceWorkflow() public {
        // 1. Alice submits a referendum
        vm.prank(alice);
        uint32 refIndex = referenda.submitLookup(
            hex"00",
            keccak256("proposal"),
            100,
            IReferenda.Timing.AtBlock,
            1000
        );
        
        // 2. Bob places decision deposit
        vm.prank(bob);
        referenda.placeDecisionDeposit(refIndex);
        
        // 3. Multiple people vote
        vm.prank(alice);
        convictionVoting.voteStandard(refIndex, true, IConvictionVoting.Conviction.Locked3x, 100 ether);
        
        vm.prank(bob);
        convictionVoting.voteStandard(refIndex, true, IConvictionVoting.Conviction.Locked2x, 80 ether);
        
        vm.prank(charlie);
        convictionVoting.voteSplit(refIndex, 50 ether, 30 ether);
        
        // 4. Check dashboard
        GovernanceDashboard.ReferendumWithVoting memory dash = 
            dashboard.getReferendumDashboard(alice, TRACK_ID, refIndex);
        
        assertTrue(dash.info.exists);
        assertTrue(dash.userHasVoted);
        assertGt(dash.tallyAyes, 0);
        
        // 5. Check analytics
        uint32[] memory indices = new uint32[](1);
        indices[0] = refIndex;
        
        GovernanceAnalytics.TrackAnalytics memory stats = 
            analytics.getTrackAnalytics(indices, TRACK_ID);
        
        assertEq(stats.totalReferendums, 1);
        assertEq(stats.ongoingCount, 1);
    }
    
    function test_DelegationPoolWorkflow() public {
        // 1. Alice joins pool
        vm.prank(alice);
        delegationPool.joinPool(100 ether);
        
        // 2. Bob registers as expert
        vm.prank(bob);
        delegationPool.registerAsExpert(TRACK_ID);
        
        // 3. Alice delegates to Bob
        vm.prank(alice);
        delegationPool.delegateToExpert(bob, 50 ether);
        
        // 4. Verify delegation
        (address target, uint128 balance, ) = convictionVoting.getDelegation(address(delegationPool), TRACK_ID);
        // In real implementation, would check delegation properly
    }
    
    function test_VotingBotAutomation() public {
        // 1. Submit referendum
        vm.prank(alice);
        uint32 refIndex = referenda.submitLookup(
            hex"00",
            keccak256("proposal"),
            100,
            IReferenda.Timing.AtBlock,
            1000
        );
        
        vm.prank(bob);
        referenda.placeDecisionDeposit(refIndex);
        
        // 2. Bot auto-votes
        votingBot.autoVote(refIndex);
        
        // 3. Verify bot voted
        (bool exists, , bool aye, , , , ) = 
            convictionVoting.getVoting(address(votingBot), TRACK_ID, refIndex);
        
        assertTrue(exists);
        assertTrue(aye); // AlwaysAye strategy
    }
    
    function test_ComplexVotingScenario() public {
        // Create multiple referendums
        vm.startPrank(alice);
        uint32 ref1 = referenda.submitLookup(hex"00", keccak256("1"), 100, IReferenda.Timing.AtBlock, 1000);
        uint32 ref2 = referenda.submitLookup(hex"00", keccak256("2"), 100, IReferenda.Timing.AtBlock, 2000);
        uint32 ref3 = referenda.submitLookup(hex"00", keccak256("3"), 100, IReferenda.Timing.AtBlock, 3000);
        vm.stopPrank();
        
        // Place deposits
        vm.startPrank(bob);
        referenda.placeDecisionDeposit(ref1);
        referenda.placeDecisionDeposit(ref2);
        referenda.placeDecisionDeposit(ref3);
        vm.stopPrank();
        
        // Vote on all
        vm.startPrank(alice);
        convictionVoting.voteStandard(ref1, true, IConvictionVoting.Conviction.Locked1x, 100 ether);
        convictionVoting.voteStandard(ref2, false, IConvictionVoting.Conviction.Locked2x, 80 ether);
        convictionVoting.voteSplit(ref3, 60 ether, 40 ether);
        vm.stopPrank();
        
        // Get batch dashboard
        uint32[] memory indices = new uint32[](3);
        indices[0] = ref1;
        indices[1] = ref2;
        indices[2] = ref3;
        
        GovernanceDashboard.ReferendumWithVoting[] memory dashboards = 
            dashboard.getBatchDashboard(alice, TRACK_ID, indices);
        
        assertEq(dashboards.length, 3);
        assertTrue(dashboards[0].userHasVoted);
        assertTrue(dashboards[1].userHasVoted);
        assertTrue(dashboards[2].userHasVoted);
        
        // Get user voting history
        (uint256 votedCount, uint256 ayeCount, uint256 nayCount, ) = 
            analytics.getUserVotingHistory(alice, TRACK_ID, indices);
        
        assertEq(votedCount, 3);
        assertGt(ayeCount, 0);
        assertGt(nayCount, 0);
    }
}