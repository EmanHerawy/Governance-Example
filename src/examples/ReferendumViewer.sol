// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "../interfaces/IReferenda.sol";

/// @title Referendum Viewer
/// @notice Helper contract for reading and displaying referendum information
contract ReferendumViewer {
    IReferenda public immutable referenda;
    
    constructor(address _referenda) {
        referenda = IReferenda(_referenda);
    }
    
    /// @notice Get human-readable status string
    function getStatusString(uint32 refIndex) 
        external 
        view 
        returns (string memory) 
    {
        IReferenda.ReferendumInfo memory info = referenda.getReferendumInfo(refIndex);
        
        if (!info.exists) return "Does not exist";
        
        if (info.status == IReferenda.ReferendumStatus.Ongoing) {
            return _getOngoingString(info.ongoingPhase);
        } else if (info.status == IReferenda.ReferendumStatus.Approved) {
            return "Approved";
        } else if (info.status == IReferenda.ReferendumStatus.Rejected) {
            return "Rejected";
        } else if (info.status == IReferenda.ReferendumStatus.Cancelled) {
            return "Cancelled";
        } else if (info.status == IReferenda.ReferendumStatus.TimedOut) {
            return "Timed Out";
        }
        return "Killed";
    }
    
    function _getOngoingString(IReferenda.OngoingPhase phase) 
        internal 
        pure 
        returns (string memory) 
    {
        if (phase == IReferenda.OngoingPhase.AwaitingDeposit) return "Awaiting Deposit";
        if (phase == IReferenda.OngoingPhase.Preparing) return "Preparing";
        if (phase == IReferenda.OngoingPhase.Queued) return "Queued";
        if (phase == IReferenda.OngoingPhase.Deciding) return "Deciding";
        return "Confirming";
    }
    
    /// @notice Check if referendum needs decision deposit
    function needsDecisionDeposit(uint32 refIndex) 
        external 
        view 
        returns (bool) 
    {
        IReferenda.ReferendumInfo memory info = referenda.getReferendumInfo(refIndex);
        return info.exists && 
               info.status == IReferenda.ReferendumStatus.Ongoing &&
               info.ongoingPhase == IReferenda.OngoingPhase.AwaitingDeposit;
    }
    
    /// @notice Get multiple referendum infos in one call
    function batchGetInfo(uint32[] calldata indices) 
        external 
        view 
        returns (IReferenda.ReferendumInfo[] memory infos) 
    {
        infos = new IReferenda.ReferendumInfo[](indices.length);
        for (uint256 i = 0; i < indices.length; i++) {
            infos[i] = referenda.getReferendumInfo(indices[i]);
        }
    }
    
    /// @notice Filter ongoing referendums from a list
    function filterOngoing(uint32[] calldata indices) 
        external 
        view 
        returns (uint32[] memory ongoingIndices) 
    {
        uint256 count = 0;
        uint32[] memory temp = new uint32[](indices.length);
        
        for (uint256 i = 0; i < indices.length; i++) {
            IReferenda.ReferendumInfo memory info = referenda.getReferendumInfo(indices[i]);
            if (info.exists && info.status == IReferenda.ReferendumStatus.Ongoing) {
                temp[count++] = indices[i];
            }
        }
        
        ongoingIndices = new uint32[](count);
        for (uint256 i = 0; i < count; i++) {
            ongoingIndices[i] = temp[i];
        }
    }
    
    /// @notice Check if referendum is ready to execute (approved and past enactment block)
    function isReadyToExecute(uint32 refIndex) 
        external 
        view 
        returns (bool) 
    {
        IReferenda.ReferendumInfo memory info = referenda.getReferendumInfo(refIndex);
        return info.exists && 
               info.status == IReferenda.ReferendumStatus.Approved &&
               block.number >= info.enactmentBlock;
    }
}