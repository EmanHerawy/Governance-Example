// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../src/interfaces/IConvictionVoting.sol";
import "../src/mocks/MockConvictionVoting.sol";
import "../src/examples/ConvictionCalculator.sol";

contract ConvictionCalculatorTest is Test {
    MockConvictionVoting public convictionVoting;
    ConvictionCalculator public calculator;

    function setUp() public {
        convictionVoting = new MockConvictionVoting();
        calculator = new ConvictionCalculator(address(convictionVoting));
    }

    function test_CalculateVotingPower_AllConvictions() public {
        uint128 balance = 100 ether;

        assertEq(calculator.calculateVotingPower(balance, IConvictionVoting.Conviction.None), 10 ether);
        assertEq(calculator.calculateVotingPower(balance, IConvictionVoting.Conviction.Locked1x), 100 ether);
        assertEq(calculator.calculateVotingPower(balance, IConvictionVoting.Conviction.Locked2x), 200 ether);
        assertEq(calculator.calculateVotingPower(balance, IConvictionVoting.Conviction.Locked3x), 300 ether);
        assertEq(calculator.calculateVotingPower(balance, IConvictionVoting.Conviction.Locked4x), 400 ether);
        assertEq(calculator.calculateVotingPower(balance, IConvictionVoting.Conviction.Locked5x), 500 ether);
        assertEq(calculator.calculateVotingPower(balance, IConvictionVoting.Conviction.Locked6x), 600 ether);
    }

    function test_GetLockPeriods_AllConvictions() public {
        assertEq(calculator.getLockPeriods(IConvictionVoting.Conviction.None), 0);
        assertEq(calculator.getLockPeriods(IConvictionVoting.Conviction.Locked1x), 1);
        assertEq(calculator.getLockPeriods(IConvictionVoting.Conviction.Locked2x), 2);
        assertEq(calculator.getLockPeriods(IConvictionVoting.Conviction.Locked3x), 4);
        assertEq(calculator.getLockPeriods(IConvictionVoting.Conviction.Locked4x), 8);
        assertEq(calculator.getLockPeriods(IConvictionVoting.Conviction.Locked5x), 16);
        assertEq(calculator.getLockPeriods(IConvictionVoting.Conviction.Locked6x), 32);
    }

    function test_GetAllConvictionOptions_Fields() public {
        ConvictionCalculator.ConvictionDetails[7] memory options = calculator.getAllConvictionOptions(100 ether);

        assertEq(options.length, 7);

        assertEq(uint8(options[0].level), uint8(IConvictionVoting.Conviction.None));
        assertEq(options[0].name, "None");
        assertEq(options[0].multiplier, 1);
        assertEq(options[0].lockPeriods, 0);
        assertEq(options[0].votingPower, 10 ether);

        assertEq(uint8(options[6].level), uint8(IConvictionVoting.Conviction.Locked6x));
        assertEq(options[6].name, "Locked6x");
        assertEq(options[6].multiplier, 60);
        assertEq(options[6].lockPeriods, 32);
        assertEq(options[6].votingPower, 600 ether);
    }

    function test_FindOptimalConviction_ExactMatch() public {
        (IConvictionVoting.Conviction optimal, uint128 actualPower, bool exactMatch) =
            calculator.findOptimalConviction(100 ether, 200 ether);

        assertEq(uint8(optimal), uint8(IConvictionVoting.Conviction.Locked2x));
        assertEq(actualPower, 200 ether);
        assertTrue(exactMatch);
    }

    function test_FindOptimalConviction_NonExactChoosesClosestBelow() public {
        (IConvictionVoting.Conviction optimal, uint128 actualPower, bool exactMatch) =
            calculator.findOptimalConviction(100 ether, 250 ether);

        assertEq(uint8(optimal), uint8(IConvictionVoting.Conviction.Locked2x));
        assertEq(actualPower, 200 ether);
        assertFalse(exactMatch);
    }

    function test_FindOptimalConviction_DesiredBelowMinimumReturnsZeroPower() public {
        (IConvictionVoting.Conviction optimal, uint128 actualPower, bool exactMatch) =
            calculator.findOptimalConviction(100 ether, 5 ether);

        assertEq(uint8(optimal), uint8(IConvictionVoting.Conviction.None));
        assertEq(actualPower, 0);
        assertFalse(exactMatch);
    }

    function test_FindOptimalConviction_DesiredAboveMaximumReturnsMax() public {
        (IConvictionVoting.Conviction optimal, uint128 actualPower, bool exactMatch) =
            calculator.findOptimalConviction(100 ether, 1000 ether);

        assertEq(uint8(optimal), uint8(IConvictionVoting.Conviction.Locked6x));
        assertEq(actualPower, 600 ether);
        assertFalse(exactMatch);
    }

    function test_CompareConvictionEfficiency_FirstMoreEfficient() public {
        (, , , , string memory recommendation) = calculator.compareConvictionEfficiency(
            100 ether,
            IConvictionVoting.Conviction.None,
            IConvictionVoting.Conviction.Locked1x
        );

        assertEq(recommendation, "First conviction is more efficient");
    }

    function test_CompareConvictionEfficiency_SecondMoreEfficient() public {
        (, , , , string memory recommendation) = calculator.compareConvictionEfficiency(
            100 ether,
            IConvictionVoting.Conviction.Locked1x,
            IConvictionVoting.Conviction.None
        );

        assertEq(recommendation, "Second conviction is more efficient");
    }

    function test_CompareConvictionEfficiency_EqualEfficiency() public {
        (, , , , string memory recommendation) = calculator.compareConvictionEfficiency(
            0,
            IConvictionVoting.Conviction.None,
            IConvictionVoting.Conviction.Locked1x
        );

        assertEq(recommendation, "Both equally efficient");
    }
}
