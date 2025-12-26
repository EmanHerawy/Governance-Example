// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "../interfaces/IReferenda.sol";

/// @title Referendum DAO
/// @notice DAO that submits and manages referendums
contract ReferendumDAO {
    IReferenda public immutable referenda = IReferenda(REFERENDA_PRECOMPILE_ADDRESS);

    struct Proposal {
        bytes32 proposalHash;
        uint32 referendumIndex;
        address proposer;
        bool submitted;
        bool depositPlaced;
    }

    uint256 public proposalCount;
    mapping(uint256 => Proposal) public proposals;

    event ProposalCreated(uint256 indexed proposalId, address indexed proposer);
    event ProposalSubmitted(uint256 indexed proposalId, uint32 indexed referendumIndex);
    event DepositPlacedByDAO(uint256 indexed proposalId, uint32 indexed referendumIndex);
    
    /// @notice Create a proposal (stored locally before submission)
    function createProposal(bytes32 proposalHash) 
        external 
        returns (uint256 proposalId) 
    {
        proposalId = proposalCount++;
        proposals[proposalId] = Proposal({
            proposalHash: proposalHash,
            referendumIndex: 0,
            proposer: msg.sender,
            submitted: false,
            depositPlaced: false
        });
        
        emit ProposalCreated(proposalId, msg.sender);
    }
    
    /// @notice Submit proposal as referendum
    function submitProposal(
        uint256 proposalId,
        bytes calldata origin,
        uint32 preimageLength,
        IReferenda.Timing timing,
        uint32 enactmentMoment
    ) external {
        Proposal storage proposal = proposals[proposalId];
        require(!proposal.submitted, "Already submitted");
        require(proposal.proposer == msg.sender, "Not proposer");
        
        uint32 refIndex = referenda.submitLookup(
            origin,
            proposal.proposalHash,
            preimageLength,
            timing,
            enactmentMoment
        );
        
        proposal.referendumIndex = refIndex;
        proposal.submitted = true;
        
        emit ProposalSubmitted(proposalId, refIndex);
    }
    
    /// @notice Place decision deposit for proposal
    function placeDeposit(uint256 proposalId) external {
        Proposal storage proposal = proposals[proposalId];
        require(proposal.submitted, "Not submitted");
        require(!proposal.depositPlaced, "Already placed");
        
        referenda.placeDecisionDeposit(proposal.referendumIndex);
        proposal.depositPlaced = true;
        
        emit DepositPlacedByDAO(proposalId, proposal.referendumIndex);
    }
    
    /// @notice Get proposal referendum info
    function getProposalInfo(uint256 proposalId) 
        external 
        view 
        returns (
            Proposal memory proposal,
            IReferenda.ReferendumInfo memory refInfo
        ) 
    {
        proposal = proposals[proposalId];
        if (proposal.submitted) {
            refInfo = referenda.getReferendumInfo(proposal.referendumIndex);
        }
    }
}