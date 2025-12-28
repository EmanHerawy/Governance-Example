// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "../interfaces/IConvictionVoting.sol";

/// @title Vote Manager
/// @notice Helper contract for managing conviction votes
contract VoteManager {
    IConvictionVoting public immutable convictionVoting = IConvictionVoting(CONVICTION_VOTING_PRECOMPILE_ADDRESS);

    struct VoteInfo {
        bool exists;
        string voteTypeString;
        string convictionString;
        uint128 totalAmount;
        bool isAye;
    }
    
    /// @notice Get human-readable vote information
    function getVoteInfo(address voter, uint16 trackId, uint32 referendumIndex) 
        external 
        view 
        returns (VoteInfo memory info) 
    {
        (
            bool exists,
            IConvictionVoting.VotingType votingType,
            bool aye,
            uint128 ayeAmount,
            uint128 nayAmount,
            uint128 abstainAmount,
            IConvictionVoting.Conviction conviction
        ) = convictionVoting.getVoting(voter, trackId, referendumIndex);
        
        info.exists = exists;
        
        if (!exists) return info;
        
        // Vote type
        if (votingType == IConvictionVoting.VotingType.Standard) {
            info.voteTypeString = "Standard";
            info.isAye = aye;
            info.totalAmount = aye ? ayeAmount : nayAmount;
        } else if (votingType == IConvictionVoting.VotingType.Split) {
            info.voteTypeString = "Split";
            info.totalAmount = ayeAmount + nayAmount;
        } else {
            info.voteTypeString = "Split Abstain";
            info.totalAmount = ayeAmount + nayAmount + abstainAmount;
        }
        
        // Conviction
        info.convictionString = _getConvictionString(conviction);
    }
    
    function _getConvictionString(IConvictionVoting.Conviction conviction) 
        internal 
        pure 
        returns (string memory) 
    {
        if (conviction == IConvictionVoting.Conviction.None) return "None (0.1x)";
        if (conviction == IConvictionVoting.Conviction.Locked1x) return "Locked1x";
        if (conviction == IConvictionVoting.Conviction.Locked2x) return "Locked2x";
        if (conviction == IConvictionVoting.Conviction.Locked3x) return "Locked3x";
        if (conviction == IConvictionVoting.Conviction.Locked4x) return "Locked4x";
        if (conviction == IConvictionVoting.Conviction.Locked5x) return "Locked5x";
        return "Locked6x";
    }
    
    /// @notice Batch vote on multiple referendums
    function batchVoteStandard(
        uint32[] calldata referendumIndices,
        bool aye,
        IConvictionVoting.Conviction conviction,
        uint128 amountPerVote
    ) external returns (uint256 successCount) {
        for (uint256 i = 0; i < referendumIndices.length; i++) {
            try convictionVoting.voteStandard(
                referendumIndices[i],
                aye,
                conviction,
                amountPerVote
            ) {
                successCount++;
            } catch {
                // Continue on failure
            }
        }
    }
    
    /// @notice Batch remove votes
    function batchRemoveVotes(
        uint16 trackId,
        uint32[] calldata referendumIndices
    ) external returns (uint256 successCount) {
        for (uint256 i = 0; i < referendumIndices.length; i++) {
            try convictionVoting.removeVote(trackId, referendumIndices[i]) {
                successCount++;
            } catch {
                // Continue on failure
            }
        }
    }
    
    /// @notice Check if user has voted on any of the referendums
    function hasVotedOnAny(
        address voter,
        uint16 trackId,
        uint32[] calldata referendumIndices
    ) external view returns (bool hasVoted, uint32 firstVotedIndex) {
        for (uint256 i = 0; i < referendumIndices.length; i++) {
            (bool exists, , , , , , ) = convictionVoting.getVoting(
                voter,
                trackId,
                referendumIndices[i]
            );
            
            if (exists) {
                return (true, referendumIndices[i]);
            }
        }
        return (false, 0);
    }
    
    /// @notice Get total voting power across multiple referendums
    function getTotalVotingPower(
        address voter,
        uint16 trackId,
        uint32[] calldata referendumIndices
    ) external view returns (uint128 totalPower, uint256 voteCount) {
        for (uint256 i = 0; i < referendumIndices.length; i++) {
            (
                bool exists,
                ,
                ,
                uint128 ayeAmount,
                uint128 nayAmount,
                uint128 abstainAmount,
                
            ) = convictionVoting.getVoting(voter, trackId, referendumIndices[i]);
            
            if (exists) {
                totalPower += (ayeAmount + nayAmount + abstainAmount);
                voteCount++;
            }
        }
    }
}