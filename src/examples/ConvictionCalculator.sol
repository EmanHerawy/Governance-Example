// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "../interfaces/IConvictionVoting.sol";

/// @title Conviction Calculator
/// @notice Calculate voting power and lock periods
contract ConvictionCalculator {
    IConvictionVoting public immutable convictionVoting = IConvictionVoting(CONVICTION_VOTING_PRECOMPILE_ADDRESS);

    struct ConvictionDetails {
        IConvictionVoting.Conviction level;
        string name;
        uint256 multiplier;
        uint256 lockPeriods;
        uint128 votingPower;
    }
    
    /// @notice Calculate voting power for a given balance and conviction
    function calculateVotingPower(
        uint128 balance,
        IConvictionVoting.Conviction conviction
    ) public pure returns (uint128 votingPower) {
        if (conviction == IConvictionVoting.Conviction.None) return balance / 10;
        if (conviction == IConvictionVoting.Conviction.Locked1x) return balance;
        if (conviction == IConvictionVoting.Conviction.Locked2x) return balance * 2;
        if (conviction == IConvictionVoting.Conviction.Locked3x) return balance * 3;
        if (conviction == IConvictionVoting.Conviction.Locked4x) return balance * 4;
        if (conviction == IConvictionVoting.Conviction.Locked5x) return balance * 5;
        if (conviction == IConvictionVoting.Conviction.Locked6x) return balance * 6;
        return balance;
    }
    
    /// @notice Get lock periods for conviction level
    function getLockPeriods(IConvictionVoting.Conviction conviction) 
        public 
        pure 
        returns (uint256 periods) 
    {
        if (conviction == IConvictionVoting.Conviction.None) return 0;
        if (conviction == IConvictionVoting.Conviction.Locked1x) return 1;
        if (conviction == IConvictionVoting.Conviction.Locked2x) return 2;
        if (conviction == IConvictionVoting.Conviction.Locked3x) return 4;
        if (conviction == IConvictionVoting.Conviction.Locked4x) return 8;
        if (conviction == IConvictionVoting.Conviction.Locked5x) return 16;
        if (conviction == IConvictionVoting.Conviction.Locked6x) return 32;
        return 0;
    }
    
    /// @notice Get all conviction details for a balance
    function getAllConvictionOptions(uint128 balance) 
        external 
        pure 
        returns (ConvictionDetails[7] memory options) 
    {
        IConvictionVoting.Conviction[7] memory convictions = [
            IConvictionVoting.Conviction.None,
            IConvictionVoting.Conviction.Locked1x,
            IConvictionVoting.Conviction.Locked2x,
            IConvictionVoting.Conviction.Locked3x,
            IConvictionVoting.Conviction.Locked4x,
            IConvictionVoting.Conviction.Locked5x,
            IConvictionVoting.Conviction.Locked6x
        ];
        
        string[7] memory names = [
            "None",
            "Locked1x",
            "Locked2x",
            "Locked3x",
            "Locked4x",
            "Locked5x",
            "Locked6x"
        ];
        
        uint256[7] memory multipliers = [uint256(1), 10, 20, 30, 40, 50, 60];
        
        for (uint256 i = 0; i < 7; i++) {
            options[i] = ConvictionDetails({
                level: convictions[i],
                name: names[i],
                multiplier: multipliers[i],
                lockPeriods: getLockPeriods(convictions[i]),
                votingPower: calculateVotingPower(balance, convictions[i])
            });
        }
    }
    
    /// @notice Find optimal conviction for desired voting power
    function findOptimalConviction(
        uint128 balance,
        uint128 desiredPower
    ) external pure returns (
        IConvictionVoting.Conviction optimal,
        uint128 actualPower,
        bool exactMatch
    ) {
        IConvictionVoting.Conviction[7] memory convictions = [
            IConvictionVoting.Conviction.None,
            IConvictionVoting.Conviction.Locked1x,
            IConvictionVoting.Conviction.Locked2x,
            IConvictionVoting.Conviction.Locked3x,
            IConvictionVoting.Conviction.Locked4x,
            IConvictionVoting.Conviction.Locked5x,
            IConvictionVoting.Conviction.Locked6x
        ];
        
        uint128 closestPower = 0;
        optimal = IConvictionVoting.Conviction.None;
        
        for (uint256 i = 0; i < 7; i++) {
            uint128 power = calculateVotingPower(balance, convictions[i]);
            
            if (power == desiredPower) {
                return (convictions[i], power, true);
            }
            
            if (power <= desiredPower && power > closestPower) {
                closestPower = power;
                optimal = convictions[i];
                actualPower = power;
            }
        }
        
        exactMatch = false;
    }
    
    /// @notice Compare conviction efficiency
    function compareConvictionEfficiency(
        uint128 balance,
        IConvictionVoting.Conviction conv1,
        IConvictionVoting.Conviction conv2
    ) external pure returns (
        uint128 power1,
        uint128 power2,
        uint256 lockPeriods1,
        uint256 lockPeriods2,
        string memory recommendation
    ) {
        power1 = calculateVotingPower(balance, conv1);
        power2 = calculateVotingPower(balance, conv2);
        lockPeriods1 = getLockPeriods(conv1);
        lockPeriods2 = getLockPeriods(conv2);
        
        // Calculate efficiency (power per lock period)
        uint256 efficiency1 = lockPeriods1 > 0 ? uint256(power1) / lockPeriods1 : uint256(power1) * 1000;
        uint256 efficiency2 = lockPeriods2 > 0 ? uint256(power2) / lockPeriods2 : uint256(power2) * 1000;
        
        if (efficiency1 > efficiency2) {
            recommendation = "First conviction is more efficient";
        } else if (efficiency2 > efficiency1) {
            recommendation = "Second conviction is more efficient";
        } else {
            recommendation = "Both equally efficient";
        }
    }
}