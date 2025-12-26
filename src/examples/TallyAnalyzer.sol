// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "../interfaces/IConvictionVoting.sol";

/// @title Tally Analyzer
/// @notice Analyze referendum voting tallies
contract TallyAnalyzer {
    IConvictionVoting public immutable convictionVoting = IConvictionVoting(CONVICTION_VOTING_PRECOMPILE_ADDRESS);

    struct TallyAnalysis {
        bool exists;
        uint128 ayes;
        uint128 nays;
        uint128 support;
        uint128 totalVotes;
        uint256 approvalPercentage;
        uint256 participationScore;
        string outcome;
    }
    
    /// @notice Get detailed tally analysis
    function analyzeTally(uint32 referendumIndex, uint128 totalIssuance) 
        external 
        view 
        returns (TallyAnalysis memory analysis) 
    {
        (bool exists, uint128 ayes, uint128 nays, uint128 support) = 
            convictionVoting.getReferendumTally(referendumIndex);
        
        analysis.exists = exists;
        
        if (!exists) return analysis;
        
        analysis.ayes = ayes;
        analysis.nays = nays;
        analysis.support = support;
        analysis.totalVotes = ayes + nays;
        
        // Calculate approval percentage
        if (analysis.totalVotes > 0) {
            analysis.approvalPercentage = (uint256(ayes) * 100) / uint256(analysis.totalVotes);
        }
        
        // Calculate participation score
        if (totalIssuance > 0) {
            analysis.participationScore = (uint256(support) * 100) / uint256(totalIssuance);
        }
        
        // Determine outcome
        if (analysis.approvalPercentage >= 75) {
            analysis.outcome = "Strong Approval";
        } else if (analysis.approvalPercentage >= 60) {
            analysis.outcome = "Moderate Approval";
        } else if (analysis.approvalPercentage >= 50) {
            analysis.outcome = "Weak Approval";
        } else if (analysis.approvalPercentage >= 40) {
            analysis.outcome = "Weak Rejection";
        } else {
            analysis.outcome = "Strong Rejection";
        }
    }
    
    /// @notice Compare tallies of multiple referendums
    function compareTallies(uint32[] calldata referendumIndices) 
        external 
        view 
        returns (
            uint32 mostAyes,
            uint32 mostNays,
            uint32 mostSupport,
            uint32 mostContested
        ) 
    {
        uint128 maxAyes = 0;
        uint128 maxNays = 0;
        uint128 maxSupport = 0;
        uint128 maxDifference = 0;
        
        for (uint256 i = 0; i < referendumIndices.length; i++) {
            (bool exists, uint128 ayes, uint128 nays, uint128 support) = 
                convictionVoting.getReferendumTally(referendumIndices[i]);
            
            if (!exists) continue;
            
            if (ayes > maxAyes) {
                maxAyes = ayes;
                mostAyes = referendumIndices[i];
            }
            
            if (nays > maxNays) {
                maxNays = nays;
                mostNays = referendumIndices[i];
            }
            
            if (support > maxSupport) {
                maxSupport = support;
                mostSupport = referendumIndices[i];
            }
            
            uint128 difference = ayes > nays ? ayes - nays : nays - ayes;
            if (difference < maxDifference || maxDifference == 0) {
                maxDifference = difference;
                mostContested = referendumIndices[i];
            }
        }
    }
    
    /// @notice Get aggregate statistics for multiple referendums
    function getAggregateStats(uint32[] calldata referendumIndices) 
        external 
        view 
        returns (
            uint256 totalReferendums,
            uint128 totalAyes,
            uint128 totalNays,
            uint128 totalSupport,
            uint128 avgAyes,
            uint128 avgNays
        ) 
    {
        for (uint256 i = 0; i < referendumIndices.length; i++) {
            (bool exists, uint128 ayes, uint128 nays, uint128 support) = 
                convictionVoting.getReferendumTally(referendumIndices[i]);
            
            if (!exists) continue;
            
            totalReferendums++;
            totalAyes += ayes;
            totalNays += nays;
            totalSupport += support;
        }
        
        if (totalReferendums > 0) {
            avgAyes = totalAyes / uint128(totalReferendums);
            avgNays = totalNays / uint128(totalReferendums);
        }
    }
    
    /// @notice Check if referendum meets quorum
    function meetsQuorum(
        uint32 referendumIndex,
        uint128 totalIssuance,
        uint256 quorumPercentage
    ) external view returns (bool meets, uint128 required, uint128 actual) {
        (, , , uint128 support) = convictionVoting.getReferendumTally(referendumIndex);
        
        required = uint128((uint256(totalIssuance) * quorumPercentage) / 100);
        actual = support;
        meets = actual >= required;
    }
    
    /// @notice Get voting trend (increasing/decreasing support)
    function getVotingTrend(uint32[] calldata referendumIndices) 
        external 
        view 
        returns (string memory trend) 
    {
        if (referendumIndices.length < 2) return "Insufficient data";
        
        uint128 firstSupport;
        uint128 lastSupport;
        
        for (uint256 i = 0; i < referendumIndices.length; i++) {
            (bool exists, , , uint128 support) = 
                convictionVoting.getReferendumTally(referendumIndices[i]);
            
            if (!exists) continue;
            
            if (i == 0) firstSupport = support;
            if (i == referendumIndices.length - 1) lastSupport = support;
        }
        
        if (lastSupport > firstSupport * 11 / 10) return "Strongly Increasing";
        if (lastSupport > firstSupport) return "Increasing";
        if (lastSupport < firstSupport * 9 / 10) return "Strongly Decreasing";
        if (lastSupport < firstSupport) return "Decreasing";
        return "Stable";
    }
}