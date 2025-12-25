// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "../interfaces/IReferenda.sol";
import "../interfaces/IConvictionVoting.sol";

/// @title Governance Analytics
/// @notice Advanced analytics combining referenda and voting data
contract GovernanceAnalytics {
    IReferenda public immutable referenda;
    IConvictionVoting public immutable convictionVoting;
    
    struct TrackAnalytics {
        uint256 totalReferendums;
        uint256 ongoingCount;
        uint256 approvedCount;
        uint256 rejectedCount;
        uint128 totalVotesCast;
        uint128 avgParticipation;
    }
    
    constructor(address _referenda, address _convictionVoting) {
        referenda = IReferenda(_referenda);
        convictionVoting = IConvictionVoting(_convictionVoting);
    }
    
    /// @notice Get track analytics
    function getTrackAnalytics(uint32[] calldata indices, uint16 trackId) 
        external 
        view 
        returns (TrackAnalytics memory analytics) 
    {
        for (uint256 i = 0; i < indices.length; i++) {
            IReferenda.ReferendumInfo memory info = referenda.getReferendumInfo(indices[i]);
            
            if (!info.exists || info.trackId != trackId) continue;
            
            analytics.totalReferendums++;
            
            if (info.status == IReferenda.ReferendumStatus.Ongoing) {
                analytics.ongoingCount++;
            } else if (info.status == IReferenda.ReferendumStatus.Approved) {
                analytics.approvedCount++;
            } else if (info.status == IReferenda.ReferendumStatus.Rejected) {
                analytics.rejectedCount++;
            }
            
            (bool tallyExists, uint128 ayes, uint128 nays, uint128 support) = 
                convictionVoting.getReferendumTally(indices[i]);
            
            if (tallyExists) {
                analytics.totalVotesCast += (ayes + nays);
                analytics.avgParticipation += support;
            }
        }
        
        if (analytics.totalReferendums > 0) {
            analytics.avgParticipation /= uint128(analytics.totalReferendums);
        }
    }
    
    /// @notice Get user voting history
    function getUserVotingHistory(
        address user,
        uint16 trackId,
        uint32[] calldata indices
    ) external view returns (
        uint256 votedCount,
        uint256 ayeCount,
        uint256 nayCount,
        uint128 totalVoted
    ) {
        for (uint256 i = 0; i < indices.length; i++) {
            (
                bool exists,
                IConvictionVoting.VotingType votingType,
                bool aye,
                uint128 ayeAmount,
                uint128 nayAmount,
                ,
                
            ) = convictionVoting.getVoting(user, trackId, indices[i]);
            
            if (!exists) continue;
            
            votedCount++;
            
            if (votingType == IConvictionVoting.VotingType.Standard) {
                if (aye) {
                    ayeCount++;
                    totalVoted += ayeAmount;
                } else {
                    nayCount++;
                    totalVoted += nayAmount;
                }
            } else {
                totalVoted += (ayeAmount + nayAmount);
                if (ayeAmount > nayAmount) ayeCount++;
                else if (nayAmount > ayeAmount) nayCount++;
            }
        }
    }
    
    /// @notice Calculate approval rate for recent referendums
    function getApprovalRate(uint32[] calldata indices, uint16 trackId) 
        external 
        view 
        returns (uint256 approvalRate) 
    {
        uint256 total = 0;
        uint256 approved = 0;
        
        for (uint256 i = 0; i < indices.length; i++) {
            IReferenda.ReferendumInfo memory info = referenda.getReferendumInfo(indices[i]);
            
            if (!info.exists || info.trackId != trackId) continue;
            if (info.status == IReferenda.ReferendumStatus.Ongoing) continue;
            
            total++;
            if (info.status == IReferenda.ReferendumStatus.Approved) {
                approved++;
            }
        }
        
        if (total > 0) {
            approvalRate = (approved * 100) / total;
        }
    }
}