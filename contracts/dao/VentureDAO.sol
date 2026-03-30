// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "../token/OMNIToken.sol";

/**
 * @title VentureDAO
 * @dev DAO for guild investments and venture management
 * @notice Allows guilds to:
 * - Pool funds for contracts
 * - Invest in projects
 * - Distribute profits
 * - Manage guild treasury
 * - Vote on investments
 */
contract VentureDAO is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant GUILD_MEMBER_ROLE = keccak256("GUILD_MEMBER_ROLE");
    bytes32 public constant GUILD_ADMIN_ROLE = keccak256("GUILD_ADMIN_ROLE");
    bytes32 public constant INVESTOR_ROLE = keccak256("INVESTOR_ROLE");
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");

    // Contract references
    OMNIToken public omniToken;

    // Guild structure
    struct Guild {
        uint256 guildId;
        string name;
        string description;
        address admin;
        uint256 treasury;
        uint256 memberCount;
        uint256 createdAt;
        bool isActive;
        string skillFocus; // e.g., "Web Development", "AI/ML"
    }

    // Investment proposal
    struct InvestmentProposal {
        uint256 proposalId;
        uint256 guildId;
        address proposer;
        string title;
        string description;
        uint256 amount;
        address recipient;
        bytes data; // Encoded investment terms
        uint256 createdAt;
        uint256 votingEnd;
        uint256 forVotes;
        uint256 againstVotes;
        bool executed;
        bool cancelled;
    }

    // Guild member
    struct GuildMember {
        address member;
        uint256 guildId;
        uint256 joinedAt;
        uint256 contribution;
        uint256 sharePercentage; // Basis points (100 = 1%)
        bool isActive;
    }

    // Storage
    mapping(uint256 => Guild) public guilds;
    mapping(uint256 => InvestmentProposal) public investmentProposals;
    mapping(uint256 => mapping(address => GuildMember)) public guildMembers;
    mapping(uint256 => address[]) public guildMemberList;
    mapping(address => uint256[]) public userGuilds;
    mapping(uint256 => mapping(address => bool)) public investmentVotes;
    
    uint256 public guildCount;
    uint256 public proposalCount;
    uint256 public investmentVotingPeriod = 5 days;
    uint256 public minInvestmentAmount = 100 * 1e18; // 100 OMNI
    uint256 public guildTaxRate = 500; // 5% in basis points

    // Events
    event GuildCreated(uint256 indexed guildId, string name, address admin);
    event GuildMemberAdded(uint256 indexed guildId, address indexed member, uint256 sharePercentage);
    event GuildMemberRemoved(uint256 indexed guildId, address indexed member);
    event InvestmentProposalCreated(
        uint256 indexed proposalId,
        uint256 indexed guildId,
        address indexed proposer,
        string title,
        uint256 amount
    );
    event InvestmentVoteCast(uint256 indexed proposalId, address indexed voter, bool support);
    event InvestmentExecuted(uint256 indexed proposalId, uint256 amount, address recipient);
    event InvestmentCancelled(uint256 indexed proposalId);
    event ProfitDistributed(uint256 indexed guildId, uint256 totalProfit);
    event TreasuryDeposited(uint256 indexed guildId, address indexed depositor, uint256 amount);
    event TreasuryWithdrawn(uint256 indexed guildId, address indexed recipient, uint256 amount);

    /**
     * @dev Constructor initializes the Venture DAO
     * @param _omniToken Address of OMNI token contract
     */
    constructor(address _omniToken) {
        require(_omniToken != address(0), "DAO: Invalid token address");
        
        omniToken = OMNIToken(_omniToken);
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(GUILD_ADMIN_ROLE, msg.sender);
        _grantRole(INVESTOR_ROLE, msg.sender);
        _grantRole(GOVERNANCE_ROLE, msg.sender);
    }

    /**
     * @dev Creates a new guild
     * @param name Guild name
     * @param description Guild description
     * @param skillFocus Skill focus area
     * @return guildId The created guild ID
     */
    function createGuild(
        string calldata name,
        string calldata description,
        string calldata skillFocus
    ) external onlyRole(GUILD_ADMIN_ROLE) whenNotPaused returns (uint256) {
        require(bytes(name).length > 0, "DAO: Empty name");
        
        guildCount++;
        uint256 guildId = guildCount;
        
        guilds[guildId] = Guild({
            guildId: guildId,
            name: name,
            description: description,
            admin: msg.sender,
            treasury: 0,
            memberCount: 1,
            createdAt: block.timestamp,
            isActive: true,
            skillFocus: skillFocus
        });
        
        // Add creator as first member with 100% share
        guildMembers[guildId][msg.sender] = GuildMember({
            member: msg.sender,
            guildId: guildId,
            joinedAt: block.timestamp,
            contribution: 0,
            sharePercentage: 10000, // 100%
            isActive: true
        });
        
        guildMemberList[guildId].push(msg.sender);
        userGuilds[msg.sender].push(guildId);
        
        emit GuildCreated(guildId, name, msg.sender);
        
        return guildId;
    }

    /**
     * @dev Adds a member to a guild
     * @param guildId Guild ID
     * @param member Member address
     * @param sharePercentage Share percentage in basis points
     */
    function addGuildMember(
        uint256 guildId,
        address member,
        uint256 sharePercentage
    ) external {
        Guild storage guild = guilds[guildId];
        require(guild.isActive, "DAO: Guild not active");
        require(msg.sender == guild.admin || hasRole(GOVERNANCE_ROLE, msg.sender), "DAO: Not authorized");
        require(member != address(0), "DAO: Invalid member");
        require(guildMembers[guildId][member].sharePercentage == 0, "DAO: Already member");
        
        // Adjust existing shares
        uint256 totalShares = _getTotalShares(guildId);
        require(totalShares + sharePercentage <= 10000, "DAO: Shares exceed 100%");
        
        guildMembers[guildId][member] = GuildMember({
            member: member,
            guildId: guildId,
            joinedAt: block.timestamp,
            contribution: 0,
            sharePercentage: sharePercentage,
            isActive: true
        });
        
        guildMemberList[guildId].push(member);
        userGuilds[member].push(guildId);
        guild.memberCount++;
        
        emit GuildMemberAdded(guildId, member, sharePercentage);
    }

    /**
     * @dev Removes a member from a guild
     * @param guildId Guild ID
     * @param member Member address
     */
    function removeGuildMember(uint256 guildId, address member) external {
        Guild storage guild = guilds[guildId];
        require(msg.sender == guild.admin || hasRole(GOVERNANCE_ROLE, msg.sender), "DAO: Not authorized");
        require(guildMembers[guildId][member].isActive, "DAO: Not active member");
        
        guildMembers[guildId][member].isActive = false;
        guild.memberCount--;
        
        emit GuildMemberRemoved(guildId, member);
    }

    /**
     * @dev Deposits funds to guild treasury
     * @param guildId Guild ID
     */
    function depositToTreasury(uint256 guildId) external payable whenNotPaused {
        Guild storage guild = guilds[guildId];
        require(guild.isActive, "DAO: Guild not active");
        require(msg.value > 0, "DAO: No value sent");
        
        // Convert ETH to OMNI (simplified - in production would use DEX)
        uint256 omniAmount = msg.value * 1000; // Placeholder conversion rate
        
        guild.treasury += omniAmount;
        guildMembers[guildId][msg.sender].contribution += omniAmount;
        
        omniToken.mint(address(this), omniAmount, "Guild Treasury Deposit");
        
        emit TreasuryDeposited(guildId, msg.sender, omniAmount);
    }

    /**
     * @dev Creates an investment proposal
     * @param guildId Guild ID
     * @param title Proposal title
     * @param description Proposal description
     * @param amount Investment amount
     * @param recipient Investment recipient
     * @param data Investment terms
     * @return proposalId The created proposal ID
     */
    function createInvestmentProposal(
        uint256 guildId,
        string calldata title,
        string calldata description,
        uint256 amount,
        address recipient,
        bytes calldata data
    ) external whenNotPaused returns (uint256) {
        Guild storage guild = guilds[guildId];
        require(guild.isActive, "DAO: Guild not active");
        require(guildMembers[guildId][msg.sender].isActive, "DAO: Not guild member");
        require(amount >= minInvestmentAmount, "DAO: Below minimum");
        require(amount <= guild.treasury, "DAO: Insufficient treasury");
        require(recipient != address(0), "DAO: Invalid recipient");
        
        proposalCount++;
        uint256 proposalId = proposalCount;
        
        investmentProposals[proposalId] = InvestmentProposal({
            proposalId: proposalId,
            guildId: guildId,
            proposer: msg.sender,
            title: title,
            description: description,
            amount: amount,
            recipient: recipient,
            data: data,
            createdAt: block.timestamp,
            votingEnd: block.timestamp + investmentVotingPeriod,
            forVotes: 0,
            againstVotes: 0,
            executed: false,
            cancelled: false
        });
        
        emit InvestmentProposalCreated(proposalId, guildId, msg.sender, title, amount);
        
        return proposalId;
    }

    /**
     * @dev Casts a vote on an investment proposal
     * @param proposalId Proposal ID
     * @param support Whether to support the proposal
     */
    function castInvestmentVote(uint256 proposalId, bool support) external whenNotPaused {
        InvestmentProposal storage proposal = investmentProposals[proposalId];
        require(!proposal.executed && !proposal.cancelled, "DAO: Proposal finalized");
        require(block.timestamp <= proposal.votingEnd, "DAO: Voting ended");
        require(!investmentVotes[proposalId][msg.sender], "DAO: Already voted");
        require(guildMembers[proposal.guildId][msg.sender].isActive, "DAO: Not guild member");
        
        // Vote weight based on share percentage
        uint256 weight = guildMembers[proposal.guildId][msg.sender].sharePercentage;
        
        if (support) {
            proposal.forVotes += weight;
        } else {
            proposal.againstVotes += weight;
        }
        
        investmentVotes[proposalId][msg.sender] = true;
        
        emit InvestmentVoteCast(proposalId, msg.sender, support);
    }

    /**
     * @dev Executes a passed investment proposal
     * @param proposalId Proposal ID
     */
    function executeInvestment(uint256 proposalId) external nonReentrant {
        InvestmentProposal storage proposal = investmentProposals[proposalId];
        require(!proposal.executed && !proposal.cancelled, "DAO: Proposal finalized");
        require(block.timestamp > proposal.votingEnd, "DAO: Voting not ended");
        
        Guild storage guild = guilds[proposal.guildId];
        require(proposal.amount <= guild.treasury, "DAO: Insufficient treasury");
        
        // Check if proposal passed (simple majority)
        require(proposal.forVotes > proposal.againstVotes, "DAO: Proposal not passed");
        
        // Execute investment
        guild.treasury -= proposal.amount;
        proposal.executed = true;
        
        // Transfer OMNI tokens
        omniToken.transfer(proposal.recipient, proposal.amount);
        
        emit InvestmentExecuted(proposalId, proposal.amount, proposal.recipient);
    }

    /**
     * @dev Cancels an investment proposal
     * @param proposalId Proposal ID
     */
    function cancelInvestment(uint256 proposalId) external {
        InvestmentProposal storage proposal = investmentProposals[proposalId];
        require(msg.sender == proposal.proposer || hasRole(GOVERNANCE_ROLE, msg.sender), "DAO: Not authorized");
        require(!proposal.executed && !proposal.cancelled, "DAO: Already finalized");
        
        proposal.cancelled = true;
        
        emit InvestmentCancelled(proposalId);
    }

    /**
     * @dev Distributes profits to guild members
     * @param guildId Guild ID
     * @param profitAmount Total profit to distribute
     */
    function distributeProfits(uint256 guildId, uint256 profitAmount) external onlyRole(GOVERNANCE_ROLE) nonReentrant {
        Guild storage guild = guilds[guildId];
        require(guild.isActive, "DAO: Guild not active");
        require(profitAmount > 0, "DAO: No profit");
        
        // Apply guild tax (5%)
        uint256 taxAmount = (profitAmount * guildTaxRate) / 10000;
        uint256 distributableProfit = profitAmount - taxAmount;
        
        // Distribute to members based on share percentage
        address[] memory members = guildMemberList[guildId];
        for (uint256 i = 0; i < members.length; i++) {
            if (guildMembers[guildId][members[i]].isActive) {
                uint256 memberShare = (distributableProfit * guildMembers[guildId][members[i]].sharePercentage) / 10000;
                if (memberShare > 0) {
                    omniToken.mint(members[i], memberShare, "Guild Profit Distribution");
                }
            }
        }
        
        // Mint tax to protocol treasury
        if (taxAmount > 0) {
            omniToken.mint(address(this), taxAmount, "Guild Tax");
        }
        
        emit ProfitDistributed(guildId, profitAmount);
    }

    /**
     * @dev Gets total shares for a guild
     * @param guildId Guild ID
     * @return Total shares in basis points
     */
    function _getTotalShares(uint256 guildId) internal view returns (uint256) {
        uint256 total = 0;
        address[] memory members = guildMemberList[guildId];
        for (uint256 i = 0; i < members.length; i++) {
            if (guildMembers[guildId][members[i]].isActive) {
                total += guildMembers[guildId][members[i]].sharePercentage;
            }
        }
        return total;
    }

    /**
     * @dev Gets guild details
     * @param guildId Guild ID
     * @return Guild data
     */
    function getGuild(uint256 guildId) external view returns (Guild memory) {
        return guilds[guildId];
    }

    /**
     * @dev Gets guild member details
     * @param guildId Guild ID
     * @param member Member address
     * @return GuildMember data
     */
    function getGuildMember(uint256 guildId, address member) external view returns (GuildMember memory) {
        return guildMembers[guildId][member];
    }

    /**
     * @dev Gets investment proposal details
     * @param proposalId Proposal ID
     * @return InvestmentProposal data
     */
    function getInvestmentProposal(uint256 proposalId) external view returns (InvestmentProposal memory) {
        return investmentProposals[proposalId];
    }

    /**
     * @dev Gets guild members list
     * @param guildId Guild ID
     * @return Array of member addresses
     */
    function getGuildMembers(uint256 guildId) external view returns (address[] memory) {
        return guildMemberList[guildId];
    }

    /**
     * @dev Gets user's guilds
     * @param user User address
     * @return Array of guild IDs
     */
    function getUserGuilds(address user) external view returns (uint256[] memory) {
        return userGuilds[user];
    }

    /**
     * @dev Updates investment voting period
     * @param newPeriod New voting period in seconds
     */
    function updateInvestmentVotingPeriod(uint256 newPeriod) external onlyRole(GOVERNANCE_ROLE) {
        require(newPeriod >= 1 days && newPeriod <= 14 days, "DAO: Invalid period");
        investmentVotingPeriod = newPeriod;
    }

    /**
     * @dev Updates minimum investment amount
     * @param newMinimum New minimum in OMNI
     */
    function updateMinInvestmentAmount(uint256 newMinimum) external onlyRole(GOVERNANCE_ROLE) {
        minInvestmentAmount = newMinimum;
    }

    /**
     * @dev Updates guild tax rate
     * @param newRate New tax rate in basis points (max 10%)
     */
    function updateGuildTaxRate(uint256 newRate) external onlyRole(GOVERNANCE_ROLE) {
        require(newRate <= 1000, "DAO: Rate too high"); // Max 10%
        guildTaxRate = newRate;
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
