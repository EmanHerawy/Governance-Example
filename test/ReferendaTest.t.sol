// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../src/interfaces/IReferenda.sol";
import "../src/mocks/MockReferenda.sol";

contract ReferendaTest is Test {
    MockReferenda public referenda;
    
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);
    
    // Test data
    bytes public constant ORIGIN = hex"00"; // Simple SCALE-encoded origin
    bytes32 public constant PROPOSAL_HASH = keccak256("test proposal");
    bytes public constant PROPOSAL_DATA = "test proposal data";
    uint32 public constant PREIMAGE_LENGTH = 100;
    
    event ReferendumSubmitted(uint32 indexed referendumIndex, address indexed submitter);
    event DecisionDepositPlaced(uint32 indexed referendumIndex, address indexed depositor);
    
    function setUp() public {
        referenda = new MockReferenda();
        
        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
        vm.label(charlie, "Charlie");
    }
    
    /* ========== SUBMIT TESTS ========== */
    
    function test_SubmitLookup_AtBlock() public {
        vm.startPrank(alice);
        
        uint32 enactmentBlock = 1000;
        
        vm.expectEmit(true, true, false, true);
        emit ReferendumSubmitted(0, alice);
        
        uint32 refIndex = referenda.submitLookup(
            ORIGIN,
            PROPOSAL_HASH,
            PREIMAGE_LENGTH,
            IReferenda.Timing.AtBlock,
            enactmentBlock
        );
        
        assertEq(refIndex, 0, "First referendum should be index 0");
        
        IReferenda.ReferendumInfo memory info = referenda.getReferendumInfo(refIndex);
        
        assertTrue(info.exists, "Referendum should exist");
        assertEq(uint8(info.status), uint8(IReferenda.ReferendumStatus.Ongoing));
        assertEq(uint8(info.ongoingPhase), uint8(IReferenda.OngoingPhase.AwaitingDeposit));
        assertEq(info.proposalHash, PROPOSAL_HASH);
        assertEq(info.enactmentBlock, enactmentBlock);
        assertEq(info.submissionBlock, uint32(block.number));
        assertEq(info.decisionDeposit, 0, "Decision deposit should be 0 initially");
        
        vm.stopPrank();
    }
    
    function test_SubmitLookup_AfterBlock() public {
        vm.startPrank(alice);
        
        uint32 blocksDelay = 100;
        uint32 currentBlock = uint32(block.number);
        
        uint32 refIndex = referenda.submitLookup(
            ORIGIN,
            PROPOSAL_HASH,
            PREIMAGE_LENGTH,
            IReferenda.Timing.AfterBlock,
            blocksDelay
        );
        
        IReferenda.ReferendumInfo memory info = referenda.getReferendumInfo(refIndex);
        
        assertEq(info.enactmentBlock, currentBlock + blocksDelay, "Enactment should be current + delay");
        
        vm.stopPrank();
    }
    
    function test_SubmitInline() public {
        vm.startPrank(alice);
        
        uint32 refIndex = referenda.submitInline(
            ORIGIN,
            PROPOSAL_DATA,
            IReferenda.Timing.AfterBlock,
            100
        );
        
        IReferenda.ReferendumInfo memory info = referenda.getReferendumInfo(refIndex);
        
        assertTrue(info.exists);
        assertEq(info.proposalHash, keccak256(PROPOSAL_DATA), "Hash should match proposal data");
        
        vm.stopPrank();
    }
    
    function test_SubmitMultiple() public {
        vm.startPrank(alice);
        
        uint32 ref1 = referenda.submitLookup(ORIGIN, PROPOSAL_HASH, PREIMAGE_LENGTH, IReferenda.Timing.AtBlock, 1000);
        uint32 ref2 = referenda.submitLookup(ORIGIN, keccak256("proposal 2"), PREIMAGE_LENGTH, IReferenda.Timing.AtBlock, 2000);
        uint32 ref3 = referenda.submitLookup(ORIGIN, keccak256("proposal 3"), PREIMAGE_LENGTH, IReferenda.Timing.AtBlock, 3000);
        
        assertEq(ref1, 0);
        assertEq(ref2, 1);
        assertEq(ref3, 2);
        
        assertTrue(referenda.getReferendumInfo(ref1).exists);
        assertTrue(referenda.getReferendumInfo(ref2).exists);
        assertTrue(referenda.getReferendumInfo(ref3).exists);
        
        vm.stopPrank();
    }
    
    /* ========== DECISION DEPOSIT TESTS ========== */
    
    function test_PlaceDecisionDeposit() public {
        vm.prank(alice);
        uint32 refIndex = referenda.submitLookup(ORIGIN, PROPOSAL_HASH, PREIMAGE_LENGTH, IReferenda.Timing.AtBlock, 1000);
        
        IReferenda.ReferendumInfo memory infoBefore = referenda.getReferendumInfo(refIndex);
        assertEq(infoBefore.decisionDeposit, 0);
        assertEq(uint8(infoBefore.ongoingPhase), uint8(IReferenda.OngoingPhase.AwaitingDeposit));
        
        vm.prank(bob);
        vm.expectEmit(true, true, false, true);
        emit DecisionDepositPlaced(refIndex, bob);
        
        referenda.placeDecisionDeposit(refIndex);
        
        IReferenda.ReferendumInfo memory infoAfter = referenda.getReferendumInfo(refIndex);
        assertGt(infoAfter.decisionDeposit, 0, "Decision deposit should be placed");
        assertEq(uint8(infoAfter.ongoingPhase), uint8(IReferenda.OngoingPhase.Preparing));
    }
    
    function test_PlaceDecisionDeposit_RevertIfNotExists() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("ReferendumNotFound(uint32)", 999));
        referenda.placeDecisionDeposit(999);
    }
    
    function test_PlaceDecisionDeposit_RevertIfAlreadyPlaced() public {
        vm.prank(alice);
        uint32 refIndex = referenda.submitLookup(ORIGIN, PROPOSAL_HASH, PREIMAGE_LENGTH, IReferenda.Timing.AtBlock, 1000);
        
        vm.prank(bob);
        referenda.placeDecisionDeposit(refIndex);
        
        vm.prank(charlie);
        vm.expectRevert(abi.encodeWithSignature("DecisionDepositAlreadyPlaced(uint32)", refIndex));
        referenda.placeDecisionDeposit(refIndex);
    }
    
    function test_PlaceDecisionDeposit_RevertIfNotOngoing() public {
        vm.prank(alice);
        uint32 refIndex = referenda.submitLookup(ORIGIN, PROPOSAL_HASH, PREIMAGE_LENGTH, IReferenda.Timing.AtBlock, 1000);
        
        // Simulate referendum being approved
        referenda._setStatus(refIndex, IReferenda.ReferendumStatus.Approved);
        
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSignature("InvalidStatus(uint32)", refIndex));
        referenda.placeDecisionDeposit(refIndex);
    }
    
    /* ========== METADATA TESTS ========== */
    
    function test_SetMetadata() public {
        vm.prank(alice);
        uint32 refIndex = referenda.submitLookup(ORIGIN, PROPOSAL_HASH, PREIMAGE_LENGTH, IReferenda.Timing.AtBlock, 1000);
        
        bytes32 metadataHash = keccak256("metadata");
        
        vm.prank(alice);
        referenda.setMetadata(refIndex, metadataHash);
        // Success if no revert
    }
    
    function test_SetMetadata_RevertIfNotSubmitter() public {
        vm.prank(alice);
        uint32 refIndex = referenda.submitLookup(ORIGIN, PROPOSAL_HASH, PREIMAGE_LENGTH, IReferenda.Timing.AtBlock, 1000);
        
        bytes32 metadataHash = keccak256("metadata");
        
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSignature("NotSubmitter(uint32)", refIndex));
        referenda.setMetadata(refIndex, metadataHash);
    }
    
    function test_ClearMetadata() public {
        vm.prank(alice);
        uint32 refIndex = referenda.submitLookup(ORIGIN, PROPOSAL_HASH, PREIMAGE_LENGTH, IReferenda.Timing.AtBlock, 1000);
        
        bytes32 metadataHash = keccak256("metadata");
        
        vm.prank(alice);
        referenda.setMetadata(refIndex, metadataHash);
        
        vm.prank(alice);
        referenda.clearMetadata(refIndex);
    }
    
    /* ========== REFUND TESTS ========== */
    
    function test_RefundSubmissionDeposit() public {
        vm.prank(alice);
        uint32 refIndex = referenda.submitLookup(ORIGIN, PROPOSAL_HASH, PREIMAGE_LENGTH, IReferenda.Timing.AtBlock, 1000);
        
        IReferenda.ReferendumInfo memory infoBefore = referenda.getReferendumInfo(refIndex);
        uint128 expectedRefund = infoBefore.submissionDeposit;
        assertGt(expectedRefund, 0, "Should have submission deposit");
        
        uint128 refundAmount = referenda.refundSubmissionDeposit(refIndex);
        
        assertEq(refundAmount, expectedRefund, "Refund amount should match deposit");
        
        IReferenda.ReferendumInfo memory infoAfter = referenda.getReferendumInfo(refIndex);
        assertEq(infoAfter.submissionDeposit, 0, "Deposit should be cleared");
    }
    
    function test_RefundDecisionDeposit() public {
        vm.prank(alice);
        uint32 refIndex = referenda.submitLookup(ORIGIN, PROPOSAL_HASH, PREIMAGE_LENGTH, IReferenda.Timing.AtBlock, 1000);
        
        vm.prank(bob);
        referenda.placeDecisionDeposit(refIndex);
        
        IReferenda.ReferendumInfo memory infoBefore = referenda.getReferendumInfo(refIndex);
        uint128 expectedRefund = infoBefore.decisionDeposit;
        assertGt(expectedRefund, 0, "Should have decision deposit");
        
        uint128 refundAmount = referenda.refundDecisionDeposit(refIndex);
        
        assertEq(refundAmount, expectedRefund, "Refund amount should match deposit");
        
        IReferenda.ReferendumInfo memory infoAfter = referenda.getReferendumInfo(refIndex);
        assertEq(infoAfter.decisionDeposit, 0, "Deposit should be cleared");
    }
    
    /* ========== VIEW FUNCTION TESTS ========== */
    
    function test_GetReferendumInfo_NonExistent() public {
        IReferenda.ReferendumInfo memory info = referenda.getReferendumInfo(999);
        assertFalse(info.exists, "Non-existent referendum should not exist");
    }
    
    function test_IsReferendumPassing() public {
        vm.prank(alice);
        uint32 refIndex = referenda.submitLookup(ORIGIN, PROPOSAL_HASH, PREIMAGE_LENGTH, IReferenda.Timing.AtBlock, 1000);
        
        (bool exists, bool passing) = referenda.isReferendumPassing(refIndex);
        assertTrue(exists, "Referendum should exist");
        assertTrue(passing, "Ongoing referendum should be passing in mock");
        
        // Test non-existent
        (bool exists2, bool passing2) = referenda.isReferendumPassing(999);
        assertFalse(exists2, "Non-existent should not exist");
        assertFalse(passing2, "Non-existent should not be passing");
    }
    
    function test_DecisionDeposit() public {
        uint128 deposit = referenda.decisionDeposit(0);
        assertGt(deposit, 0, "Decision deposit should be positive");
    }
    
    function test_SubmissionDeposit() public {
        uint128 deposit = referenda.submissionDeposit();
        assertGt(deposit, 0, "Submission deposit should be positive");
    }
    
    /* ========== STATUS TRANSITION TESTS ========== */
    
    function test_StatusTransitions() public {
        vm.prank(alice);
        uint32 refIndex = referenda.submitLookup(ORIGIN, PROPOSAL_HASH, PREIMAGE_LENGTH, IReferenda.Timing.AtBlock, 1000);
        
        // Initial state
        IReferenda.ReferendumInfo memory info = referenda.getReferendumInfo(refIndex);
        assertEq(uint8(info.status), uint8(IReferenda.ReferendumStatus.Ongoing));
        
        // Transition to Approved
        referenda._setStatus(refIndex, IReferenda.ReferendumStatus.Approved);
        info = referenda.getReferendumInfo(refIndex);
        assertEq(uint8(info.status), uint8(IReferenda.ReferendumStatus.Approved));
        
        // Transition to Rejected
        referenda._setStatus(refIndex, IReferenda.ReferendumStatus.Rejected);
        info = referenda.getReferendumInfo(refIndex);
        assertEq(uint8(info.status), uint8(IReferenda.ReferendumStatus.Rejected));
        
        // Transition to Cancelled
        referenda._setStatus(refIndex, IReferenda.ReferendumStatus.Cancelled);
        info = referenda.getReferendumInfo(refIndex);
        assertEq(uint8(info.status), uint8(IReferenda.ReferendumStatus.Cancelled));
        
        // Transition to TimedOut
        referenda._setStatus(refIndex, IReferenda.ReferendumStatus.TimedOut);
        info = referenda.getReferendumInfo(refIndex);
        assertEq(uint8(info.status), uint8(IReferenda.ReferendumStatus.TimedOut));
        
        // Transition to Killed
        referenda._setStatus(refIndex, IReferenda.ReferendumStatus.Killed);
        info = referenda.getReferendumInfo(refIndex);
        assertEq(uint8(info.status), uint8(IReferenda.ReferendumStatus.Killed));
    }
    
    function test_OngoingPhaseTransitions() public {
        vm.prank(alice);
        uint32 refIndex = referenda.submitLookup(ORIGIN, PROPOSAL_HASH, PREIMAGE_LENGTH, IReferenda.Timing.AtBlock, 1000);
        
        // Initial phase
        IReferenda.ReferendumInfo memory info = referenda.getReferendumInfo(refIndex);
        assertEq(uint8(info.ongoingPhase), uint8(IReferenda.OngoingPhase.AwaitingDeposit));
        
        // Place deposit moves to Preparing
        vm.prank(bob);
        referenda.placeDecisionDeposit(refIndex);
        info = referenda.getReferendumInfo(refIndex);
        assertEq(uint8(info.ongoingPhase), uint8(IReferenda.OngoingPhase.Preparing));
        
        // Test other phases
        referenda._setPhase(refIndex, IReferenda.OngoingPhase.Queued);
        info = referenda.getReferendumInfo(refIndex);
        assertEq(uint8(info.ongoingPhase), uint8(IReferenda.OngoingPhase.Queued));
        
        referenda._setPhase(refIndex, IReferenda.OngoingPhase.Deciding);
        info = referenda.getReferendumInfo(refIndex);
        assertEq(uint8(info.ongoingPhase), uint8(IReferenda.OngoingPhase.Deciding));
        
        referenda._setPhase(refIndex, IReferenda.OngoingPhase.Confirming);
        info = referenda.getReferendumInfo(refIndex);
        assertEq(uint8(info.ongoingPhase), uint8(IReferenda.OngoingPhase.Confirming));
    }
    
    /* ========== STRUCT USAGE TESTS ========== */
    
    function test_StructFieldAccess() public {
        vm.prank(alice);
        uint32 refIndex = referenda.submitLookup(ORIGIN, PROPOSAL_HASH, PREIMAGE_LENGTH, IReferenda.Timing.AtBlock, 1000);
        
        // Test that struct allows clean field access
        IReferenda.ReferendumInfo memory info = referenda.getReferendumInfo(refIndex);
        
        // All fields should be accessible by name
        bool _exists = info.exists;
        IReferenda.ReferendumStatus _status = info.status;
        IReferenda.OngoingPhase _phase = info.ongoingPhase;
        uint16 _trackId = info.trackId;
        bytes32 _hash = info.proposalHash;
        uint128 _subDeposit = info.submissionDeposit;
        uint128 _decDeposit = info.decisionDeposit;
        uint32 _enactBlock = info.enactmentBlock;
        uint32 _subBlock = info.submissionBlock;
        
        // Verify values
        assertTrue(_exists);
        assertEq(uint8(_status), uint8(IReferenda.ReferendumStatus.Ongoing));
        assertEq(_hash, PROPOSAL_HASH);
    }
    
    function test_StructInMemory() public {
        vm.prank(alice);
        uint32 refIndex = referenda.submitLookup(ORIGIN, PROPOSAL_HASH, PREIMAGE_LENGTH, IReferenda.Timing.AtBlock, 1000);
        
        // Test that struct can be passed around
        IReferenda.ReferendumInfo memory info = referenda.getReferendumInfo(refIndex);
        _helperCheckInfo(info);
    }
    
    function _helperCheckInfo(IReferenda.ReferendumInfo memory info) internal {
        assertTrue(info.exists);
        assertEq(info.proposalHash, PROPOSAL_HASH);
    }
    
    /* ========== FUZZ TESTS ========== */
    
    function testFuzz_SubmitLookup(
        bytes32 proposalHash,
        uint32 preimageLength,
        uint32 enactmentMoment
    ) public {
        vm.assume(enactmentMoment > 0);
        vm.assume(enactmentMoment < type(uint32).max - uint32(block.number));
        
        vm.prank(alice);
        uint32 refIndex = referenda.submitLookup(
            ORIGIN,
            proposalHash,
            preimageLength,
            IReferenda.Timing.AfterBlock,
            enactmentMoment
        );
        
        IReferenda.ReferendumInfo memory info = referenda.getReferendumInfo(refIndex);
        assertTrue(info.exists);
        assertEq(info.proposalHash, proposalHash);
    }
    
    function testFuzz_MultipleSubmissions(uint8 count) public {
        vm.assume(count > 0 && count <= 20);
        
        vm.startPrank(alice);
        for (uint8 i = 0; i < count; i++) {
            uint32 refIndex = referenda.submitLookup(
                ORIGIN,
                bytes32(uint256(i)),
                PREIMAGE_LENGTH,
                IReferenda.Timing.AtBlock,
                1000 + i
            );
            assertEq(refIndex, i);
        }
        vm.stopPrank();
    }
    
    /* ========== INTEGRATION TESTS ========== */
    
    function test_CompleteWorkflow() public {
        // Alice submits
        vm.prank(alice);
        uint32 refIndex = referenda.submitLookup(
            ORIGIN,
            PROPOSAL_HASH,
            PREIMAGE_LENGTH,
            IReferenda.Timing.AtBlock,
            1000
        );
        
        // Check initial state
        IReferenda.ReferendumInfo memory info = referenda.getReferendumInfo(refIndex);
        assertTrue(info.exists);
        assertEq(uint8(info.status), uint8(IReferenda.ReferendumStatus.Ongoing));
        assertEq(uint8(info.ongoingPhase), uint8(IReferenda.OngoingPhase.AwaitingDeposit));
        
        // Bob places decision deposit
        vm.prank(bob);
        referenda.placeDecisionDeposit(refIndex);
        
        info = referenda.getReferendumInfo(refIndex);
        assertGt(info.decisionDeposit, 0);
        assertEq(uint8(info.ongoingPhase), uint8(IReferenda.OngoingPhase.Preparing));
        
        // Alice sets metadata
        vm.prank(alice);
        referenda.setMetadata(refIndex, keccak256("ipfs://..."));
        
        // Simulate approval
        referenda._setStatus(refIndex, IReferenda.ReferendumStatus.Approved);
        
        info = referenda.getReferendumInfo(refIndex);
        assertEq(uint8(info.status), uint8(IReferenda.ReferendumStatus.Approved));
        
        // Refund deposits
        uint128 subRefund = referenda.refundSubmissionDeposit(refIndex);
        uint128 decRefund = referenda.refundDecisionDeposit(refIndex);
        
        assertGt(subRefund, 0);
        assertGt(decRefund, 0);
        
        info = referenda.getReferendumInfo(refIndex);
        assertEq(info.submissionDeposit, 0);
        assertEq(info.decisionDeposit, 0);
    }
    
    /* ========== GAS BENCHMARKS ========== */
    
    function testGas_SubmitLookup() public {
        vm.prank(alice);
        referenda.submitLookup(ORIGIN, PROPOSAL_HASH, PREIMAGE_LENGTH, IReferenda.Timing.AtBlock, 1000);
    }
    
    function testGas_GetReferendumInfo() public view {
        referenda.getReferendumInfo(0);
    }
    
    function testGas_PlaceDecisionDeposit() public {
        vm.prank(alice);
        uint32 refIndex = referenda.submitLookup(ORIGIN, PROPOSAL_HASH, PREIMAGE_LENGTH, IReferenda.Timing.AtBlock, 1000);
        
        vm.prank(bob);
        referenda.placeDecisionDeposit(refIndex);
    }
}