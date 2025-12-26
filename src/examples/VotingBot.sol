// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "../interfaces/IReferenda.sol";
import "../interfaces/IConvictionVoting.sol";

/// @title Automated Voting Bot
/// @notice Automatically votes on referendums based on predefined strategies
contract VotingBot {
    IReferenda public immutable referenda = IReferenda(REFERENDA_PRECOMPILE_ADDRESS);
    IConvictionVoting public immutable convictionVoting = IConvictionVoting(CONVICTION_VOTING_PRECOMPILE_ADDRESS);

    address public owner;
    uint16 public trackId;

    enum VoteStrategy {
        AlwaysAye,
        AlwaysNay,
        FollowDelegate,
        BasedOnTally
    }

    VoteStrategy public strategy;
    address public delegateToFollow;
    IConvictionVoting.Conviction public defaultConviction;
    uint128 public voteAmount;

    event AutoVoted(uint32 indexed referendumIndex, bool aye, uint128 amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor(
        uint16 _trackId,
        VoteStrategy _strategy,
        uint128 _voteAmount
    ) {
        owner = msg.sender;
        trackId = _trackId;
        strategy = _strategy;
        voteAmount = _voteAmount;
        defaultConviction = IConvictionVoting.Conviction.Locked3x;
    }
    
    /// @notice Automatically vote on a referendum based on strategy
    function autoVote(uint32 referendumIndex) external {
        IReferenda.ReferendumInfo memory info = referenda.getReferendumInfo(referendumIndex);
        require(info.exists, "Referendum does not exist");
        require(info.status == IReferenda.ReferendumStatus.Ongoing, "Not ongoing");
        
        bool shouldVoteAye = _determineVote(referendumIndex);
        
        convictionVoting.voteStandard(
            referendumIndex,
            shouldVoteAye,
            defaultConviction,
            voteAmount
        );
        
        emit AutoVoted(referendumIndex, shouldVoteAye, voteAmount);
    }
    
    function _determineVote(uint32 referendumIndex) internal view returns (bool aye) {
        if (strategy == VoteStrategy.AlwaysAye) {
            return true;
        } else if (strategy == VoteStrategy.AlwaysNay) {
            return false;
        } else if (strategy == VoteStrategy.FollowDelegate) {
            require(delegateToFollow != address(0), "No delegate set");
            
            (bool voteExists, , bool delegateAye, , , , ) = 
                convictionVoting.getVoting(delegateToFollow, trackId, referendumIndex);
            
            require(voteExists, "Delegate hasn't voted");
            return delegateAye;
        } else if (strategy == VoteStrategy.BasedOnTally) {
            (bool exists, uint128 ayes, uint128 nays, ) = 
                convictionVoting.getReferendumTally(referendumIndex);
            
            require(exists, "No tally available");
            return ayes > nays; // Vote with majority
        }
        
        return true; // Default to aye
    }
    
    /// @notice Update strategy
    function setStrategy(VoteStrategy newStrategy) external onlyOwner {
        strategy = newStrategy;
    }
    
    /// @notice Set delegate to follow
    function setDelegateToFollow(address newDelegate) external onlyOwner {
        delegateToFollow = newDelegate;
    }
    
    /// @notice Update vote parameters
    function setVoteParams(
        uint128 newAmount,
        IConvictionVoting.Conviction newConviction
    ) external onlyOwner {
        voteAmount = newAmount;
        defaultConviction = newConviction;
    }
}