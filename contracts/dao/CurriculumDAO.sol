// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "../token/OMNIToken.sol";

/**
 * @title CurriculumDAO
 * @dev Decentralized governance for curriculum decisions
 * @notice Allows token holders to:
 * - Propose new courses
 * - Vote on curriculum changes
 * - Allocate learning rewards
 * - Approve instructors
 * - Set skill standards
 */
contract CurriculumDAO is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant MEMBER_ROLE = keccak256("MEMBER_ROLE");
    bytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");

    // Contract references
    OMNIToken public omniToken;

    // Proposal types
    enum ProposalType {
        NEW_COURSE,
        CURRICULUM_UPDATE,
        REWARD_ALLOCATION,
        INSTRUCTOR_APPROVAL,
        SKILL_STANDARD,
        BUDGET_ALLOCATION,
        POLICY_CHANGE
    }

    // Vote options
    enum VoteOption {
        AGAINST,
        FOR,
        ABSTAIN
    }

    // Proposal status
    enum ProposalStatus {
        PENDING,
        ACTIVE,
        PASSED,
        FAILED,
        EXECUTED,
        CANCELLED
    }

    // Proposal structure
    struct Proposal {
        uint256 proposalId;
        address proposer;
        ProposalType proposalType;
        string title;
        string description;
        bytes data; // Encoded function call
        uint256 createdAt;
        uint256 votingStart;
        uint256 votingEnd;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 abstainVotes;
        uint256 quorum;
        ProposalStatus status;
        bool executed;
    }

    // Vote record
    struct Vote {
        uint256 proposalId;
        address voter;
        VoteOption option;
        uint256 weight;
        uint256 timestamp;
    }

    // Storage
    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => Vote)) public votes;
    mapping(address => uint256[]) public userProposals;
    mapping(address => uint256[]) public userVotes;
    
    uint256 public proposalCount;
    uint256 public votingPeriod = 7 days;
    uint256 public quorumPercentage = 10; // 10% of total supply
    uint256 public proposalThreshold = 1000 * 1e18; // 1000 OMNI to create proposal

    // Events
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        ProposalType proposalType,
        string title,
        uint256 votingStart,
        uint256 votingEnd
    );
    event VoteCast(
        uint256 indexed proposalId,
        address indexed voter,
        VoteOption option,
        uint256 weight
    );
    event ProposalExecuted(uint256 indexed proposalId);
    event ProposalCancelled(uint256 indexed proposalId);
    event VotingPeriodUpdated(uint256 newPeriod);
    event QuorumUpdated(uint256 newQuorum);
    event ProposalThresholdUpdated(uint256 newThreshold);

    /**
     * @dev Constructor initializes the Curriculum DAO
     * @param _omniToken Address of OMNI token contract
     */
    constructor(address _omniToken) {
        require(_omniToken != address(0), "DAO: Invalid token address");
        
        omniToken = OMNIToken(_omniToken);
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MEMBER_ROLE, msg.sender);
        _grantRole(PROPOSER_ROLE, msg.sender);
        _grantRole(GOVERNANCE_ROLE, msg.sender);
    }

    /**
     * @dev Creates a new proposal
     * @param proposalType Type of proposal
     * @param title Proposal title
     * @param description Detailed description
     * @param data Encoded function call for execution
     * @return proposalId The created proposal ID
     */
    function createProposal(
        ProposalType proposalType,
        string calldata title,
        string calldata description,
        bytes calldata data
    ) external onlyRole(PROPOSER_ROLE) whenNotPaused nonReentrant returns (uint256) {
        require(omniToken.balanceOf(msg.sender) >= proposalThreshold, "DAO: Insufficient tokens for proposal");
        
        proposalCount++;
        uint256 proposalId = proposalCount;
        
        uint256 votingStart = block.timestamp + 1 days; // 1 day delay
        uint256 votingEnd = votingStart + votingPeriod;
        
        proposals[proposalId] = Proposal({
            proposalId: proposalId,
            proposer: msg.sender,
            proposalType: proposalType,
            title: title,
            description: description,
            data: data,
            createdAt: block.timestamp,
            votingStart: votingStart,
            votingEnd: votingEnd,
            forVotes: 0,
            againstVotes: 0,
            abstainVotes: 0,
            quorum: (omniToken.totalSupply() * quorumPercentage) / 100,
            status: ProposalStatus.PENDING,
            executed: false
        });
        
        userProposals[msg.sender].push(proposalId);
        
        emit ProposalCreated(proposalId, msg.sender, proposalType, title, votingStart, votingEnd);
        
        return proposalId;
    }

    /**
     * @dev Casts a vote on a proposal
     * @param proposalId Proposal ID
     * @param option Vote option (FOR, AGAINST, ABSTAIN)
     */
    function castVote(uint256 proposalId, VoteOption option) external whenNotPaused {
        Proposal storage proposal = proposals[proposalId];
        
        require(block.timestamp >= proposal.votingStart, "DAO: Voting not started");
        require(block.timestamp <= proposal.votingEnd, "DAO: Voting ended");
        require(proposal.status == ProposalStatus.PENDING || proposal.status == ProposalStatus.ACTIVE, 
            "DAO: Proposal not active");
        require(votes[proposalId][msg.sender].weight == 0, "DAO: Already voted");
        
        // Calculate vote weight based on token balance
        uint256 weight = omniToken.balanceOf(msg.sender);
        require(weight > 0, "DAO: No voting power");
        
        // Update proposal status to active
        if (proposal.status == ProposalStatus.PENDING) {
            proposal.status = ProposalStatus.ACTIVE;
        }
        
        // Record vote
        votes[proposalId][msg.sender] = Vote({
            proposalId: proposalId,
            voter: msg.sender,
            option: option,
            weight: weight,
            timestamp: block.timestamp
        });
        
        // Update vote counts
        if (option == VoteOption.FOR) {
            proposal.forVotes += weight;
        } else if (option == VoteOption.AGAINST) {
            proposal.againstVotes += weight;
        } else {
            proposal.abstainVotes += weight;
        }
        
        userVotes[msg.sender].push(proposalId);
        
        emit VoteCast(proposalId, msg.sender, option, weight);
    }

    /**
     * @dev Executes a passed proposal
     * @param proposalId Proposal ID
     */
    function executeProposal(uint256 proposalId) external onlyRole(GOVERNANCE_ROLE) nonReentrant {
        Proposal storage proposal = proposals[proposalId];
        
        require(block.timestamp > proposal.votingEnd, "DAO: Voting not ended");
        require(proposal.status == ProposalStatus.ACTIVE, "DAO: Proposal not active");
        require(!proposal.executed, "DAO: Already executed");
        
        // Check if proposal passed
        bool passed = _checkProposalPassed(proposalId);
        
        if (passed) {
            proposal.status = ProposalStatus.PASSED;
            
            // Execute proposal data
            if (proposal.data.length > 0) {
                (bool success, ) = address(this).call(proposal.data);
                require(success, "DAO: Execution failed");
            }
            
            proposal.executed = true;
            proposal.status = ProposalStatus.EXECUTED;
            
            emit ProposalExecuted(proposalId);
        } else {
            proposal.status = ProposalStatus.FAILED;
        }
    }

    /**
     * @dev Cancels a proposal
     * @param proposalId Proposal ID
     */
    function cancelProposal(uint256 proposalId) external {
        Proposal storage proposal = proposals[proposalId];
        
        require(msg.sender == proposal.proposer || hasRole(GOVERNANCE_ROLE, msg.sender), 
            "DAO: Not authorized");
        require(proposal.status == ProposalStatus.PENDING || proposal.status == ProposalStatus.ACTIVE, 
            "DAO: Cannot cancel");
        
        proposal.status = ProposalStatus.CANCELLED;
        
        emit ProposalCancelled(proposalId);
    }

    /**
     * @dev Checks if a proposal has passed
     * @param proposalId Proposal ID
     * @return Whether proposal passed
     */
    function _checkProposalPassed(uint256 proposalId) internal view returns (bool) {
        Proposal storage proposal = proposals[proposalId];
        
        // Check quorum
        uint256 totalVotes = proposal.forVotes + proposal.againstVotes + proposal.abstainVotes;
        if (totalVotes < proposal.quorum) {
            return false;
        }
        
        // Check majority
        return proposal.forVotes > proposal.againstVotes;
    }

    /**
     * @dev Gets proposal details
     * @param proposalId Proposal ID
     * @return Proposal data
     */
    function getProposal(uint256 proposalId) external view returns (Proposal memory) {
        return proposals[proposalId];
    }

    /**
     * @dev Gets vote details
     * @param proposalId Proposal ID
     * @param voter Voter address
     * @return Vote data
     */
    function getVote(uint256 proposalId, address voter) external view returns (Vote memory) {
        return votes[proposalId][voter];
    }

    /**
     * @dev Gets user's proposals
     * @param user User address
     * @return Array of proposal IDs
     */
    function getUserProposals(address user) external view returns (uint256[] memory) {
        return userProposals[user];
    }

    /**
     * @dev Gets user's votes
     * @param user User address
     * @return Array of proposal IDs
     */
    function getUserVotes(address user) external view returns (uint256[] memory) {
        return userVotes[user];
    }

    /**
     * @dev Updates voting period
     * @param newPeriod New voting period in seconds
     */
    function updateVotingPeriod(uint256 newPeriod) external onlyRole(GOVERNANCE_ROLE) {
        require(newPeriod >= 1 days && newPeriod <= 30 days, "DAO: Invalid period");
        votingPeriod = newPeriod;
        emit VotingPeriodUpdated(newPeriod);
    }

    /**
     * @dev Updates quorum percentage
     * @param newQuorum New quorum percentage (1-100)
     */
    function updateQuorum(uint256 newQuorum) external onlyRole(GOVERNANCE_ROLE) {
        require(newQuorum >= 1 && newQuorum <= 100, "DAO: Invalid quorum");
        quorumPercentage = newQuorum;
        emit QuorumUpdated(newQuorum);
    }

    /**
     * @dev Updates proposal threshold
     * @param newThreshold New threshold in OMNI
     */
    function updateProposalThreshold(uint256 newThreshold) external onlyRole(GOVERNANCE_ROLE) {
        proposalThreshold = newThreshold;
        emit ProposalThresholdUpdated(newThreshold);
    }

    /**
     * @dev Pauses the contract
     */
    function pause() external onlyRole(GOVERNANCE_ROLE) {
        _pause();
    }

    /**
     * @dev Unpauses the contract
     */
    function unpause() external onlyRole(GOVERNANCE_ROLE) {
        _unpause();
    }
}
