// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "../interfaces/IReferenda.sol";
import "../interfaces/IConvictionVoting.sol";

/// @title Delegation Pool
/// @notice Pool voting power and delegate to expert voters
contract DelegationPool {
    IReferenda public immutable referenda = IReferenda(REFERENDA_PRECOMPILE_ADDRESS);
    IConvictionVoting public immutable convictionVoting = IConvictionVoting(CONVICTION_VOTING_PRECOMPILE_ADDRESS);

    struct Member {
        uint128 balance;
        bool isActive;
    }

    struct Expert {
        uint128 totalDelegated;
        uint16 trackId;
        bool isActive;
    }

    mapping(address => Member) public members;
    mapping(address => Expert) public experts;

    uint128 public totalPooled;

    event MemberJoined(address indexed member, uint128 amount);
    event MemberLeft(address indexed member, uint128 amount);
    event DelegatedToExpert(address indexed expert, uint16 trackId, uint128 amount);
    
    /// @notice Join the pool with tokens
    function joinPool(uint128 amount) external {
        require(amount > 0, "Amount must be positive");
        
        if (!members[msg.sender].isActive) {
            members[msg.sender].isActive = true;
        }
        
        members[msg.sender].balance += amount;
        totalPooled += amount;
        
        emit MemberJoined(msg.sender, amount);
    }
    
    /// @notice Leave the pool and withdraw
    function leavePool() external {
        require(members[msg.sender].isActive, "Not a member");
        
        uint128 amount = members[msg.sender].balance;
        
        members[msg.sender].balance = 0;
        members[msg.sender].isActive = false;
        totalPooled -= amount;
        
        emit MemberLeft(msg.sender, amount);
    }
    
    /// @notice Register as an expert voter
    function registerAsExpert(uint16 trackId) external {
        experts[msg.sender] = Expert({
            totalDelegated: 0,
            trackId: trackId,
            isActive: true
        });
    }
    
    /// @notice Delegate pool power to an expert
    function delegateToExpert(address expert, uint128 amount) external {
        require(experts[expert].isActive, "Not an active expert");
        require(members[msg.sender].balance >= amount, "Insufficient balance");
        
        uint16 trackId = experts[expert].trackId;
        
        convictionVoting.delegate(
            trackId,
            expert,
            IConvictionVoting.Conviction.Locked2x,
            amount
        );
        
        experts[expert].totalDelegated += amount;
        members[msg.sender].balance -= amount;
        
        emit DelegatedToExpert(expert, trackId, amount);
    }
    
    /// @notice Get pool statistics
    function getPoolStats() external view returns (
        uint128 total,
        uint256 memberCount,
        uint256 expertCount
    ) {
        total = totalPooled;
        // Member and expert counts would require tracking in production
    }
}