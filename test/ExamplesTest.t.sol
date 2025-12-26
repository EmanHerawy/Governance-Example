// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../src/interfaces/IReferenda.sol";
import "../src/mocks/MockReferenda.sol";
import "../src/examples/ReferendumViewer.sol";
import "../src/examples/ReferendumManager.sol";
import "../src/examples/ReferendumDAO.sol";

contract ExamplesTest is Test {
    MockReferenda public referenda;
    ReferendumViewer public viewer;
    ReferendumManager public manager;
    ReferendumDAO public dao;

    address public alice = address(0x1);

    function setUp() public {
        // Deploy mock and copy its code to the precompile address
        MockReferenda mockImpl = new MockReferenda();
        vm.etch(REFERENDA_PRECOMPILE_ADDRESS, address(mockImpl).code);
        referenda = MockReferenda(REFERENDA_PRECOMPILE_ADDRESS);

        viewer = new ReferendumViewer();
        manager = new ReferendumManager();
        dao = new ReferendumDAO();
    }
    
    function test_Viewer_GetStatusString() public {
        vm.prank(alice);
        uint32 refIndex = referenda.submitLookup(
            hex"00",
            keccak256("test"),
            100,
            IReferenda.Timing.AtBlock,
            1000
        );
        
        string memory status = viewer.getStatusString(refIndex);
        assertEq(status, "Awaiting Deposit");
        
        // Test non-existent
        string memory nonExistent = viewer.getStatusString(999);
        assertEq(nonExistent, "Does not exist");
    }
    
    function test_Viewer_NeedsDecisionDeposit() public {
        vm.prank(alice);
        uint32 refIndex = referenda.submitLookup(
            hex"00",
            keccak256("test"),
            100,
            IReferenda.Timing.AtBlock,
            1000
        );
        
        assertTrue(viewer.needsDecisionDeposit(refIndex));
        
        vm.prank(alice);
        referenda.placeDecisionDeposit(refIndex);
        
        assertFalse(viewer.needsDecisionDeposit(refIndex));
    }
    
    function test_Viewer_BatchGetInfo() public {
        uint32[] memory indices = new uint32[](3);
        
        vm.startPrank(alice);
        indices[0] = referenda.submitLookup(hex"00", keccak256("1"), 100, IReferenda.Timing.AtBlock, 1000);
        indices[1] = referenda.submitLookup(hex"00", keccak256("2"), 100, IReferenda.Timing.AtBlock, 2000);
        indices[2] = referenda.submitLookup(hex"00", keccak256("3"), 100, IReferenda.Timing.AtBlock, 3000);
        vm.stopPrank();
        
        IReferenda.ReferendumInfo[] memory infos = viewer.batchGetInfo(indices);
        
        assertEq(infos.length, 3);
        assertTrue(infos[0].exists);
        assertTrue(infos[1].exists);
        assertTrue(infos[2].exists);
    }
    
    function test_Manager_BatchPlaceDeposit() public {
        uint32[] memory indices = new uint32[](3);
        
        vm.startPrank(alice);
        indices[0] = referenda.submitLookup(hex"00", keccak256("1"), 100, IReferenda.Timing.AtBlock, 1000);
        indices[1] = referenda.submitLookup(hex"00", keccak256("2"), 100, IReferenda.Timing.AtBlock, 2000);
        indices[2] = referenda.submitLookup(hex"00", keccak256("3"), 100, IReferenda.Timing.AtBlock, 3000);
        vm.stopPrank();
        
        uint256 successCount = manager.batchPlaceDecisionDeposit(indices);
        assertEq(successCount, 3);
    }
    
    function test_DAO_CompleteFlow() public {
        bytes32 proposalHash = keccak256("dao proposal");
        
        vm.startPrank(alice);
        
        // Create proposal
        uint256 proposalId = dao.createProposal(proposalHash);
        assertEq(proposalId, 0);
        
        // Submit to referendum
        dao.submitProposal(
            proposalId,
            hex"00",
            100,
            IReferenda.Timing.AtBlock,
            1000
        );
        
        // Place deposit
        dao.placeDeposit(proposalId);
        
        // Get info
        (
            ReferendumDAO.Proposal memory proposal,
            IReferenda.ReferendumInfo memory refInfo
        ) = dao.getProposalInfo(proposalId);
        
        assertTrue(proposal.submitted);
        assertTrue(proposal.depositPlaced);
        assertTrue(refInfo.exists);
        assertGt(refInfo.decisionDeposit, 0);
        
        vm.stopPrank();
    }
}