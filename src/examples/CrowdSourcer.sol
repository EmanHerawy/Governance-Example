// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import "../interfaces/IReferenda.sol";

enum Status {
    Depositing,
    Deposited,
    Withdrawing
}

/**
 * @title CrowdSourcer
 * @dev Implements CrowdSourcing for decision deposits. Accepts native tokens and exposes a function that places decision deposit.
 */
contract CrowdSourcer {
    Status public status;
    IReferenda public immutable referenda;
    uint32 public immutable referendumIndex;
    uint128 public immutable targetDecisionDeposit;
    uint128 public totalContributed;

    mapping(address => uint128) public contributors;

    constructor(uint32 _referendumIndex) {
        referendumIndex = _referendumIndex;
        referenda = IReferenda(REFERENDA_PRECOMPILE_ADDRESS);
        targetDecisionDeposit = referenda.decisionDeposit(_referendumIndex);
        status = Status.Depositing;
    }

    function placeDecisionDeposit() external {
        require(
            totalContributed >= targetDecisionDeposit,
            "CrowdSourcer: Target not reached"
        );
        require(status == Status.Depositing, "CrowdSourcer: Already deposited");
        status = Status.Deposited;
        referenda.placeDecisionDeposit(referendumIndex);
    }

    function refundDecisionDeposit() external {
        require(status == Status.Deposited, "CrowdSourcer: Not deposited");
        status = Status.Withdrawing;
        referenda.refundDecisionDeposit(referendumIndex);
    }

    function withdraw() external {
        require(
            status == Status.Withdrawing,
            "CrowdSourcer: Decision Deposit not refunded"
        );
        uint128 amount = contributors[msg.sender];
        require(amount > 0, "CrowdSourcer: Not contributed");

        contributors[msg.sender] = 0;

        (bool success, ) = msg.sender.call{value: amount}("");

        require(success, "CrowdSourcer: Withdraw failed");
    }

    function contribute() external payable {
        require(status == Status.Depositing, "CrowdSourcer: Not depositing");
        require(
            msg.value <= type(uint128).max,
            "CrowdSourcer: Overflow when casting to uint128"
        );
        uint128 amount = uint128(msg.value);
        require(
            amount <= targetDecisionDeposit - totalContributed,
            "CrowdSourcer: Contributing more than neccesary"
        );
        contributors[msg.sender] += amount;
        totalContributed += amount;
    }
}
