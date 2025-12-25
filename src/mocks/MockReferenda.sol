// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "../interfaces/IReferenda.sol";

/// @title Mock Referenda Precompile
/// @notice Mock implementation for testing the IReferenda interface
/// @dev Simulates precompile behavior without actual Substrate runtime
contract MockReferenda is IReferenda {
    /* ========== STATE ========== */
    
    uint32 private nextReferendumIndex = 0;
    uint128 private constant SUBMISSION_DEPOSIT = 100 ether;
    uint128 private constant DECISION_DEPOSIT = 50 ether;
    
    mapping(uint32 => ReferendumInfo) private referendums;
    mapping(uint32 => address) private submitters;
    mapping(uint32 => address) private decisionDepositors;
    
    /* ========== EVENTS ========== */
    
    event ReferendumSubmitted(uint32 indexed referendumIndex, address indexed submitter);
    event DecisionDepositPlaced(uint32 indexed referendumIndex, address indexed depositor);
    
    /* ========== ERRORS ========== */
    
    error ReferendumNotFound(uint32 referendumIndex);
    error DecisionDepositAlreadyPlaced(uint32 referendumIndex);
    error NotSubmitter(uint32 referendumIndex);
    error InvalidStatus(uint32 referendumIndex);
    
    /* ========== WRITE FUNCTIONS ========== */
    
    function submitLookup(
        bytes calldata origin,
        bytes32 hash,
        uint32 preimageLength,
        Timing timing,
        uint32 enactmentMoment
    ) external returns (uint32 referendumIndex) {
        referendumIndex = nextReferendumIndex++;
        
        uint32 enactmentBlock = timing == Timing.AtBlock 
            ? enactmentMoment 
            : uint32(block.number) + enactmentMoment;
        
        referendums[referendumIndex] = ReferendumInfo({
            exists: true,
            status: ReferendumStatus.Ongoing,
            ongoingPhase: OngoingPhase.AwaitingDeposit,
            trackId: 0,
            proposalHash: hash,
            submissionDeposit: SUBMISSION_DEPOSIT,
            decisionDeposit: 0,
            enactmentBlock: enactmentBlock,
            submissionBlock: uint32(block.number)
        });
        
        submitters[referendumIndex] = msg.sender;
        emit ReferendumSubmitted(referendumIndex, msg.sender);
    }
    
    function submitInline(
        bytes calldata origin,
        bytes calldata proposal,
        Timing timing,
        uint32 enactmentMoment
    ) external returns (uint32 referendumIndex) {
        bytes32 hash = keccak256(proposal);
        return this.submitLookup(origin, hash, uint32(proposal.length), timing, enactmentMoment);
    }
    
    function placeDecisionDeposit(uint32 referendumIndex) external {
        ReferendumInfo storage info = referendums[referendumIndex];
        
        if (!info.exists) revert ReferendumNotFound(referendumIndex);
        if (info.decisionDeposit > 0) revert DecisionDepositAlreadyPlaced(referendumIndex);
        if (info.status != ReferendumStatus.Ongoing) revert InvalidStatus(referendumIndex);
        
        info.decisionDeposit = DECISION_DEPOSIT;
        info.ongoingPhase = OngoingPhase.Preparing;
        decisionDepositors[referendumIndex] = msg.sender;
        
        emit DecisionDepositPlaced(referendumIndex, msg.sender);
    }
    
    function setMetadata(uint32 referendumIndex, bytes32 metadataHash) external {
        if (!referendums[referendumIndex].exists) revert ReferendumNotFound(referendumIndex);
        if (submitters[referendumIndex] != msg.sender) revert NotSubmitter(referendumIndex);
        // Metadata stored in runtime, not EVM state
    }
    
    function clearMetadata(uint32 referendumIndex) external {
        if (!referendums[referendumIndex].exists) revert ReferendumNotFound(referendumIndex);
        if (submitters[referendumIndex] != msg.sender) revert NotSubmitter(referendumIndex);
    }
    
    function refundSubmissionDeposit(uint32 referendumIndex) 
        external 
        returns (uint128 refundAmount) 
    {
        ReferendumInfo storage info = referendums[referendumIndex];
        if (!info.exists) revert ReferendumNotFound(referendumIndex);
        
        refundAmount = info.submissionDeposit;
        info.submissionDeposit = 0;
    }
    
    function refundDecisionDeposit(uint32 referendumIndex) 
        external 
        returns (uint128 refundAmount) 
    {
        ReferendumInfo storage info = referendums[referendumIndex];
        if (!info.exists) revert ReferendumNotFound(referendumIndex);
        
        refundAmount = info.decisionDeposit;
        info.decisionDeposit = 0;
    }
    
    /* ========== VIEW FUNCTIONS ========== */
    
    function getReferendumInfo(uint32 referendumIndex) 
        external 
        view 
        returns (ReferendumInfo memory info) 
    {
        return referendums[referendumIndex];
    }
    
    function isReferendumPassing(uint32 referendumIndex) 
        external 
        view 
        returns (bool exists, bool passing) 
    {
        exists = referendums[referendumIndex].exists;
        passing = exists && referendums[referendumIndex].status == ReferendumStatus.Ongoing;
    }
    
    function decisionDeposit(uint32 referendumIndex) 
        external 
        pure 
        returns (uint128) 
    {
        return DECISION_DEPOSIT;
    }
    
    function submissionDeposit() external pure returns (uint128) {
        return SUBMISSION_DEPOSIT;
    }
    
    /* ========== TEST HELPERS ========== */
    
    function _setStatus(uint32 refIndex, ReferendumStatus newStatus) external {
        referendums[refIndex].status = newStatus;
    }
    
    function _setPhase(uint32 refIndex, OngoingPhase newPhase) external {
        referendums[refIndex].ongoingPhase = newPhase;
    }
}