// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "../interfaces/IReferenda.sol";
import "../interfaces/IConvictionVoting.sol";

/// @title Governance Dashboard
/// @notice Comprehensive view of governance state combining referenda and voting data
contract GovernanceDashboard {
    IReferenda public immutable referenda;
    IConvictionVoting public immutable convictionVoting;
    
    struct ReferendumWithVoting {
        IReferenda.ReferendumInfo info;
        bool userHasVoted;
        IConvictionVoting.VotingType userVoteType;
        bool userVotedAye;
        uint128 userVoteAmount;
        uint128 tallyAyes;
        uint128 tallyNays;
        uint128 tallySupport;
        bool isPassing;
    }
    
    constructor(address _referenda, address _convictionVoting) {
        referenda = IReferenda(_referenda);
        convictionVoting = IConvictionVoting(_convictionVoting);
    }
    
    /// @notice Get complete referendum dashboard for a user
    function getReferendumDashboard(
        address user,
        uint16 trackId,
        uint32 referendumIndex
    ) external view returns (ReferendumWithVoting memory dashboard) {
        // Get referendum info
        dashboard.info = referenda.getReferendumInfo(referendumIndex);
        
        // Get user's vote
        (
            bool voteExists,
            IConvictionVoting.VotingType votingType,
            bool aye,
            uint128 ayeAmount,
            uint128 nayAmount,
            ,
            
        ) = convictionVoting.getVoting(user, trackId, referendumIndex);
        
        dashboard.userHasVoted = voteExists;
        dashboard.userVoteType = votingType;
        dashboard.userVotedAye = aye;
        dashboard.userVoteAmount = ayeAmount > 0 ? ayeAmount : nayAmount;
        
        // Get tally
        (
            bool tallyExists,
            uint128 ayes,
            uint128 nays,
            uint128 support
        ) = convictionVoting.getReferendumTally(referendumIndex);
        
        if (tallyExists) {
            dashboard.tallyAyes = ayes;
            dashboard.tallyNays = nays;
            dashboard.tallySupport = support;
        }
        
        // Check if passing
        (, dashboard.isPassing) = referenda.isReferendumPassing(referendumIndex);
    }
    
    /// @notice Get multiple referendums with voting data
    function getBatchDashboard(
        address user,
        uint16 trackId,
        uint32[] calldata indices
    ) external view returns (ReferendumWithVoting[] memory dashboards) {
        dashboards = new ReferendumWithVoting[](indices.length);
        
        for (uint256 i = 0; i < indices.length; i++) {
            dashboards[i] = this.getReferendumDashboard(user, trackId, indices[i]);
        }
    }
    
    /// @notice Check if user can vote on referendum
    function canUserVote(address user, uint16 trackId, uint32 referendumIndex) 
        external 
        view 
        returns (bool canVote, string memory reason) 
    {
        IReferenda.ReferendumInfo memory info = referenda.getReferendumInfo(referendumIndex);
        
        if (!info.exists) {
            return (false, "Referendum does not exist");
        }
        
        if (info.status != IReferenda.ReferendumStatus.Ongoing) {
            return (false, "Referendum is not ongoing");
        }
        
        if (info.ongoingPhase != IReferenda.OngoingPhase.Deciding) {
            return (false, "Referendum is not in deciding phase");
        }
        
        (bool hasVoted, , , , , , ) = convictionVoting.getVoting(user, trackId, referendumIndex);
        
        if (hasVoted) {
            return (true, "Can change vote");
        }
        
        return (true, "Can vote");
    }
    
    /// @notice Get referendum health score (0-100)
    function getReferendumHealth(uint32 referendumIndex) 
        external 
        view 
        returns (uint8 healthScore, string memory status) 
    {
        IReferenda.ReferendumInfo memory info = referenda.getReferendumInfo(referendumIndex);
        
        if (!info.exists) return (0, "Does not exist");
        
        (bool tallyExists, uint128 ayes, uint128 nays, uint128 support) = 
            convictionVoting.getReferendumTally(referendumIndex);
        
        if (!tallyExists) return (50, "No votes yet");
        
        uint128 total = ayes + nays;
        if (total == 0) return (50, "No votes");
        
        // Health based on support and margin
        uint256 approvalRate = (uint256(ayes) * 100) / uint256(total);
        uint256 supportRate = (uint256(support) * 100) / 1000 ether; // Assume 1000 as quorum
        
        healthScore = uint8((approvalRate + supportRate) / 2);
        
        if (healthScore >= 75) status = "Healthy - Likely to pass";
        else if (healthScore >= 50) status = "Moderate - Uncertain";
        else status = "Weak - Likely to fail";
    }
}