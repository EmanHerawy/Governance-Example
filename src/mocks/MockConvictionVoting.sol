// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "../interfaces/IConvictionVoting.sol";

/// @title Mock ConvictionVoting Precompile
/// @notice Mock implementation for testing the IConvictionVoting interface
contract MockConvictionVoting is IConvictionVoting {
    /* ========== STRUCTS ========== */
    
    struct Vote {
        bool exists;
        VotingType votingType;
        bool aye;
        uint128 ayeAmount;
        uint128 nayAmount;
        uint128 abstainAmount;
        Conviction conviction;
    }
    
    struct Delegation {
        address target;
        uint128 balance;
        Conviction conviction;
    }
    
    struct Tally {
        bool exists;
        uint128 ayes;
        uint128 nays;
        uint128 support;
    }
    
    /* ========== STATE ========== */
    
    // who => trackId => referendumIndex => Vote
    mapping(address => mapping(uint16 => mapping(uint32 => Vote))) private votes;
    
    // who => trackId => Delegation
    mapping(address => mapping(uint16 => Delegation)) private delegations;
    
    // referendumIndex => Tally
    mapping(uint32 => Tally) private tallies;
    
    // Track locks
    mapping(address => mapping(uint16 => uint128)) private locks;
    
    /* ========== EVENTS ========== */
    
    event VoteCast(address indexed voter, uint32 indexed referendumIndex, VotingType votingType);
    event VoteRemoved(address indexed voter, uint16 indexed trackId, uint32 indexed referendumIndex);
    event Delegated(address indexed delegator, uint16 indexed trackId, address indexed target);
    event Undelegated(address indexed delegator, uint16 indexed trackId);
    event Unlocked(uint16 indexed trackId, address indexed target);
    
    /* ========== ERRORS ========== */
    
    error VoteNotFound(address who, uint16 trackId, uint32 referendumIndex);
    error InsufficientBalance(uint128 required, uint128 available);
    error InvalidVoteAmount();
    
    /* ========== WRITE FUNCTIONS ========== */
    
    function voteStandard(
        uint32 referendumIndex,
        bool aye,
        Conviction conviction,
        uint128 balance
    ) external {
        if (balance == 0) revert InvalidVoteAmount();
        
        uint16 trackId = 0; // Default track for testing
        
        votes[msg.sender][trackId][referendumIndex] = Vote({
            exists: true,
            votingType: VotingType.Standard,
            aye: aye,
            ayeAmount: aye ? balance : 0,
            nayAmount: aye ? 0 : balance,
            abstainAmount: 0,
            conviction: conviction
        });
        
        _updateTally(referendumIndex, aye, balance, conviction);
        
        emit VoteCast(msg.sender, referendumIndex, VotingType.Standard);
    }
    
    function voteSplit(
        uint32 referendumIndex,
        uint128 ayeAmount,
        uint128 nayAmount
    ) external {
        if (ayeAmount == 0 && nayAmount == 0) revert InvalidVoteAmount();
        
        uint16 trackId = 0;
        
        votes[msg.sender][trackId][referendumIndex] = Vote({
            exists: true,
            votingType: VotingType.Split,
            aye: false,
            ayeAmount: ayeAmount,
            nayAmount: nayAmount,
            abstainAmount: 0,
            conviction: Conviction.None
        });
        
        if (ayeAmount > 0) _updateTally(referendumIndex, true, ayeAmount, Conviction.None);
        if (nayAmount > 0) _updateTally(referendumIndex, false, nayAmount, Conviction.None);
        
        emit VoteCast(msg.sender, referendumIndex, VotingType.Split);
    }
    
    function voteSplitAbstain(
        uint32 referendumIndex,
        uint128 ayeAmount,
        uint128 nayAmount,
        uint128 abstainAmount
    ) external {
        if (ayeAmount == 0 && nayAmount == 0 && abstainAmount == 0) revert InvalidVoteAmount();
        
        uint16 trackId = 0;
        
        votes[msg.sender][trackId][referendumIndex] = Vote({
            exists: true,
            votingType: VotingType.SplitAbstain,
            aye: false,
            ayeAmount: ayeAmount,
            nayAmount: nayAmount,
            abstainAmount: abstainAmount,
            conviction: Conviction.None
        });
        
        if (ayeAmount > 0) _updateTally(referendumIndex, true, ayeAmount, Conviction.None);
        if (nayAmount > 0) _updateTally(referendumIndex, false, nayAmount, Conviction.None);
        
        emit VoteCast(msg.sender, referendumIndex, VotingType.SplitAbstain);
    }
    
    function removeVote(uint16 trackId, uint32 referendumIndex) external {
        if (!votes[msg.sender][trackId][referendumIndex].exists) {
            revert VoteNotFound(msg.sender, trackId, referendumIndex);
        }
        
        delete votes[msg.sender][trackId][referendumIndex];
        
        emit VoteRemoved(msg.sender, trackId, referendumIndex);
    }
    
    function delegate(
        uint16 trackId,
        address to,
        Conviction conviction,
        uint128 balance
    ) external {
        if (balance == 0) revert InvalidVoteAmount();
        
        delegations[msg.sender][trackId] = Delegation({
            target: to,
            balance: balance,
            conviction: conviction
        });
        
        emit Delegated(msg.sender, trackId, to);
    }
    
    function undelegate(uint16 trackId) external {
        delete delegations[msg.sender][trackId];
        
        emit Undelegated(msg.sender, trackId);
    }
    
    function unlock(uint16 trackId, address target) external {
        delete locks[target][trackId];
        
        emit Unlocked(trackId, target);
    }
    
    /* ========== VIEW FUNCTIONS ========== */
    
    function getVoting(
        address who,
        uint16 trackId,
        uint32 referendumIndex
    )
        external
        view
        returns (
            bool exists,
            VotingType votingType,
            bool aye,
            uint128 ayeAmount,
            uint128 nayAmount,
            uint128 abstainAmount,
            Conviction conviction
        )
    {
        Vote memory vote = votes[who][trackId][referendumIndex];
        
        exists = vote.exists;
        votingType = vote.votingType;
        aye = vote.aye;
        ayeAmount = vote.ayeAmount;
        nayAmount = vote.nayAmount;
        abstainAmount = vote.abstainAmount;
        conviction = vote.conviction;
    }
    
    function getDelegation(
        address who,
        uint16 trackId
    ) external view returns (address target, uint128 balance, Conviction conviction) {
        Delegation memory delegation = delegations[who][trackId];
        target = delegation.target;
        balance = delegation.balance;
        conviction = delegation.conviction;
    }
    
    function getReferendumTally(
        uint32 referendumIndex
    ) external view returns (bool exists, uint128 ayes, uint128 nays, uint128 support) {
        Tally memory tally = tallies[referendumIndex];
        exists = tally.exists;
        ayes = tally.ayes;
        nays = tally.nays;
        support = tally.support;
    }
    
    /* ========== INTERNAL HELPERS ========== */
    
    function _updateTally(
        uint32 referendumIndex,
        bool isAye,
        uint128 amount,
        Conviction conviction
    ) internal {
        if (!tallies[referendumIndex].exists) {
            tallies[referendumIndex].exists = true;
        }
        
        uint128 multipliedAmount = _applyConviction(amount, conviction);
        
        if (isAye) {
            tallies[referendumIndex].ayes += multipliedAmount;
            tallies[referendumIndex].support += amount;
        } else {
            tallies[referendumIndex].nays += multipliedAmount;
        }
    }
    
    function _applyConviction(uint128 amount, Conviction conviction) internal pure returns (uint128) {
        if (conviction == Conviction.None) return amount / 10;
        if (conviction == Conviction.Locked1x) return amount;
        if (conviction == Conviction.Locked2x) return amount * 2;
        if (conviction == Conviction.Locked3x) return amount * 3;
        if (conviction == Conviction.Locked4x) return amount * 4;
        if (conviction == Conviction.Locked5x) return amount * 5;
        if (conviction == Conviction.Locked6x) return amount * 6;
        return amount;
    }
    
    /* ========== TEST HELPERS ========== */
    
    function _setTally(uint32 refIndex, uint128 ayes, uint128 nays, uint128 support) external {
        tallies[refIndex] = Tally({
            exists: true,
            ayes: ayes,
            nays: nays,
            support: support
        });
    }
}