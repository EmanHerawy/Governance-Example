// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "../interfaces/IReferenda.sol";

/// @title Referendum Manager
/// @notice  Managing multiple referendums
contract ReferendumManager {
    IReferenda public immutable referenda;
    
    event BatchDepositPlaced(uint32[] indices, uint256 successCount);
    event DepositRefunded(uint32 indexed refIndex, uint128 amount);
    
    error DepositFailed(uint32 refIndex, string reason);
    
    constructor(address _referenda) {
        referenda = IReferenda(_referenda);
    }
    
    /// @notice Place decision deposits for multiple referendums
    /// @dev Continues on failure, returns success count
    function batchPlaceDecisionDeposit(uint32[] calldata indices) 
        external 
        returns (uint256 successCount) 
    {
        for (uint256 i = 0; i < indices.length; i++) {
            try referenda.placeDecisionDeposit(indices[i]) {
                successCount++;
            } catch {
                // Continue on failure
            }
        }
        
        emit BatchDepositPlaced(indices, successCount);
    }
    
    /// @notice Refund deposits for multiple completed referendums
    function batchRefundDeposits(uint32[] calldata indices) 
        external 
        returns (uint128 totalRefunded) 
    {
        for (uint256 i = 0; i < indices.length; i++) {
            IReferenda.ReferendumInfo memory info = referenda.getReferendumInfo(indices[i]);
            
            // Only refund if referendum is finished
            if (info.exists && info.status != IReferenda.ReferendumStatus.Ongoing) {
                try referenda.refundSubmissionDeposit(indices[i]) returns (uint128 amount) {
                    totalRefunded += amount;
                    emit DepositRefunded(indices[i], amount);
                } catch {}
                
                try referenda.refundDecisionDeposit(indices[i]) returns (uint128 amount) {
                    totalRefunded += amount;
                    emit DepositRefunded(indices[i], amount);
                } catch {}
            }
        }
    }
    
    /// @notice Get summary statistics for a track
    function getTrackStats(uint32[] calldata indices, uint16 trackId) 
        external 
        view 
        returns (
            uint256 total,
            uint256 ongoing,
            uint256 approved,
            uint256 rejected
        ) 
    {
        for (uint256 i = 0; i < indices.length; i++) {
            IReferenda.ReferendumInfo memory info = referenda.getReferendumInfo(indices[i]);
            
            if (info.exists && info.trackId == trackId) {
                total++;
                if (info.status == IReferenda.ReferendumStatus.Ongoing) ongoing++;
                else if (info.status == IReferenda.ReferendumStatus.Approved) approved++;
                else if (info.status == IReferenda.ReferendumStatus.Rejected) rejected++;
            }
        }
    }
}