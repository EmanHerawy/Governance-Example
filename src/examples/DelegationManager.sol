// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "../interfaces/IConvictionVoting.sol";

/// @title Delegation Manager
/// @notice Advanced delegation management
contract DelegationManager {
    IConvictionVoting public immutable convictionVoting = IConvictionVoting(CONVICTION_VOTING_PRECOMPILE_ADDRESS);

    struct DelegationInfo {
        bool isDelegating;
        address target;
        uint128 balance;
        string convictionString;
        uint128 effectiveVotingPower;
    }

    event DelegationChanged(address indexed delegator, uint16 indexed trackId, address indexed newTarget);
    event MultipleDelegationsSet(address indexed delegator, uint256 trackCount);
    
    /// @notice Get delegation info with calculated voting power
    function getDelegationInfo(address delegator, uint16 trackId) 
        external 
        view 
        returns (DelegationInfo memory info) 
    {
        (address target, uint128 balance, IConvictionVoting.Conviction conviction) = 
            convictionVoting.getDelegation(delegator, trackId);
        
        info.isDelegating = target != address(0);
        info.target = target;
        info.balance = balance;
        
        if (info.isDelegating) {
            info.convictionString = _getConvictionString(conviction);
            info.effectiveVotingPower = _calculateVotingPower(balance, conviction);
        }
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
    
    function _calculateVotingPower(uint128 balance, IConvictionVoting.Conviction conviction) 
        internal 
        pure 
        returns (uint128) 
    {
        if (conviction == IConvictionVoting.Conviction.None) return balance / 10;
        if (conviction == IConvictionVoting.Conviction.Locked1x) return balance;
        if (conviction == IConvictionVoting.Conviction.Locked2x) return balance * 2;
        if (conviction == IConvictionVoting.Conviction.Locked3x) return balance * 3;
        if (conviction == IConvictionVoting.Conviction.Locked4x) return balance * 4;
        if (conviction == IConvictionVoting.Conviction.Locked5x) return balance * 5;
        if (conviction == IConvictionVoting.Conviction.Locked6x) return balance * 6;
        return balance;
    }
    
    /// @notice Delegate to multiple tracks at once
    function batchDelegate(
        uint16[] calldata trackIds,
        address[] calldata targets,
        IConvictionVoting.Conviction[] calldata convictions,
        uint128[] calldata balances
    ) external {
        require(
            trackIds.length == targets.length &&
            targets.length == convictions.length &&
            convictions.length == balances.length,
            "Array length mismatch"
        );
        
        for (uint256 i = 0; i < trackIds.length; i++) {
            convictionVoting.delegate(trackIds[i], targets[i], convictions[i], balances[i]);
            emit DelegationChanged(msg.sender, trackIds[i], targets[i]);
        }
        
        emit MultipleDelegationsSet(msg.sender, trackIds.length);
    }
    
    /// @notice Undelegate from multiple tracks
    function batchUndelegate(uint16[] calldata trackIds) external {
        for (uint256 i = 0; i < trackIds.length; i++) {
            convictionVoting.undelegate(trackIds[i]);
            emit DelegationChanged(msg.sender, trackIds[i], address(0));
        }
    }
    
    /// @notice Get all delegations for a user across tracks
    function getBatchDelegations(
        address delegator,
        uint16[] calldata trackIds
    ) external view returns (DelegationInfo[] memory infos) {
        infos = new DelegationInfo[](trackIds.length);
        
        for (uint256 i = 0; i < trackIds.length; i++) {
            (address target, uint128 balance, IConvictionVoting.Conviction conviction) = 
                convictionVoting.getDelegation(delegator, trackIds[i]);
            
            infos[i].isDelegating = target != address(0);
            infos[i].target = target;
            infos[i].balance = balance;
            
            if (infos[i].isDelegating) {
                infos[i].convictionString = _getConvictionString(conviction);
                infos[i].effectiveVotingPower = _calculateVotingPower(balance, conviction);
            }
        }
    }
    
    /// @notice Check if user is delegating on any track
    function isDelegatingOnAnyTrack(
        address delegator,
        uint16[] calldata trackIds
    ) external view returns (bool isDelegating, uint16 firstTrack) {
        for (uint256 i = 0; i < trackIds.length; i++) {
            (address target, , ) = convictionVoting.getDelegation(delegator, trackIds[i]);
            
            if (target != address(0)) {
                return (true, trackIds[i]);
            }
        }
        return (false, 0);
    }
    
    /// @notice Redelegate - change delegation target
    function redelegate(
        uint16 trackId,
        address newTarget,
        IConvictionVoting.Conviction newConviction,
        uint128 newBalance
    ) external {
        // First undelegate
        convictionVoting.undelegate(trackId);
        
        // Then delegate to new target
        convictionVoting.delegate(trackId, newTarget, newConviction, newBalance);
        
        emit DelegationChanged(msg.sender, trackId, newTarget);
    }
}