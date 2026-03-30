// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "../token/OMNIToken.sol";
import "../sbt/SoulboundCredential.sol";

/**
 * @title LearnToEarn
 * @dev Core protocol for rewarding learning activities
 * @notice Rewards users with $OMNI tokens for:
 * - Completing course modules
 * - Submitting projects
 * - Mentoring peers
 * - Participating in guilds
 * - Achieving skill milestones
 */
contract LearnToEarn is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant CURRICULUM_ROLE = keccak256("CURRICULUM_ROLE");
    bytes32 public constant MENTOR_ROLE = keccak256("MENTOR_ROLE");
    bytes32 public constant GUILD_ROLE = keccak256("GUILD_ROLE");
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");

    // Contract references
    OMNIToken public omniToken;
    SoulboundCredential public soulboundCredential;

    // Learning activity types
    enum ActivityType {
        MODULE_COMPLETION,
        PROJECT_SUBMISSION,
        PEER_MENTORSHIP,
        GUILD_PARTICIPATION,
        SKILL_MILESTONE,
        CODE_REVIEW,
        FORUM_CONTRIBUTION,
        ATTENDANCE
    }

    // Reward structure
    struct RewardConfig {
        uint256 baseReward;
        uint256 skillMultiplier; // 1-10 scale
        uint256 timeBonus; // Bonus for completing within time limit
        uint256 streakBonus; // Bonus for consecutive days
        bool enabled;
    }

    // User learning data
    struct LearnerProfile {
        uint256 totalRewards;
        uint256 modulesCompleted;
        uint256 projectsSubmitted;
        uint256 mentorshipSessions;
        uint256 currentStreak;
        uint256 longestStreak;
        uint256 lastActivityTimestamp;
        uint256 skillPoints;
        bool isActive;
    }

    // Storage
    mapping(ActivityType => RewardConfig) public rewardConfigs;
    mapping(address => LearnerProfile) public learnerProfiles;
    mapping(address => mapping(bytes32 => bool)) public completedActivities;
    mapping(bytes32 => Activity) public activities;

    // Activity tracking
    struct Activity {
        bytes32 activityId;
        address learner;
        ActivityType activityType;
        string skillCategory;
        uint256 skillLevel;
        uint256 completedAt;
        uint256 rewardAmount;
        bool verified;
        address verifier;
    }

    // Events
    event ActivityCompleted(
        bytes32 indexed activityId,
        address indexed learner,
        ActivityType activityType,
        uint256 rewardAmount,
        string skillCategory
    );
    event RewardDistributed(address indexed learner, uint256 amount, string reason);
    event StreakUpdated(address indexed learner, uint256 newStreak);
    event SkillMilestoneReached(address indexed learner, string skill, uint256 level);
    event LearnerProfileCreated(address indexed learner);
    event RewardConfigUpdated(ActivityType activityType, uint256 newBaseReward);

    /**
     * @dev Constructor initializes the Learn-to-Earn protocol
     * @param _omniToken Address of OMNI token contract
     * @param _soulboundCredential Address of SBT contract
     */
    constructor(address _omniToken, address _soulboundCredential) {
        require(_omniToken != address(0), "L2E: Invalid token address");
        require(_soulboundCredential != address(0), "L2E: Invalid SBT address");
        
        omniToken = OMNIToken(_omniToken);
        soulboundCredential = SoulboundCredential(_soulboundCredential);
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(CURRICULUM_ROLE, msg.sender);
        _grantRole(MENTOR_ROLE, msg.sender);
        _grantRole(GUILD_ROLE, msg.sender);
        _grantRole(GOVERNANCE_ROLE, msg.sender);
        
        _initializeRewardConfigs();
    }

    /**
     * @dev Initializes default reward configurations
     */
    function _initializeRewardConfigs() internal {
        // Module completion: 10 OMNI base
        rewardConfigs[ActivityType.MODULE_COMPLETION] = RewardConfig({
            baseReward: 10 * 1e18,
            skillMultiplier: 1,
            timeBonus: 5 * 1e18, // 5 OMNI bonus for early completion
            streakBonus: 2 * 1e18, // 2 OMNI per day streak
            enabled: true
        });
        
        // Project submission: 50 OMNI base
        rewardConfigs[ActivityType.PROJECT_SUBMISSION] = RewardConfig({
            baseReward: 50 * 1e18,
            skillMultiplier: 2,
            timeBonus: 20 * 1e18,
            streakBonus: 5 * 1e18,
            enabled: true
        });
        
        // Peer mentorship: 25 OMNI per session
        rewardConfigs[ActivityType.PEER_MENTORSHIP] = RewardConfig({
            baseReward: 25 * 1e18,
            skillMultiplier: 1,
            timeBonus: 10 * 1e18,
            streakBonus: 3 * 1e18,
            enabled: true
        });
        
        // Guild participation: 15 OMNI
        rewardConfigs[ActivityType.GUILD_PARTICIPATION] = RewardConfig({
            baseReward: 15 * 1e18,
            skillMultiplier: 1,
            timeBonus: 5 * 1e18,
            streakBonus: 2 * 1e18,
            enabled: true
        });
        
        // Skill milestone: 100 OMNI
        rewardConfigs[ActivityType.SKILL_MILESTONE] = RewardConfig({
            baseReward: 100 * 1e18,
            skillMultiplier: 3,
            timeBonus: 50 * 1e18,
            streakBonus: 10 * 1e18,
            enabled: true
        });
        
        // Code review: 20 OMNI
        rewardConfigs[ActivityType.CODE_REVIEW] = RewardConfig({
            baseReward: 20 * 1e18,
            skillMultiplier: 1,
            timeBonus: 8 * 1e18,
            streakBonus: 2 * 1e18,
            enabled: true
        });
        
        // Forum contribution: 5 OMNI
        rewardConfigs[ActivityType.FORUM_CONTRIBUTION] = RewardConfig({
            baseReward: 5 * 1e18,
            skillMultiplier: 1,
            timeBonus: 2 * 1e18,
            streakBonus: 1 * 1e18,
            enabled: true
        });
        
        // Attendance: 8 OMNI
        rewardConfigs[ActivityType.ATTENDANCE] = RewardConfig({
            baseReward: 8 * 1e18,
            skillMultiplier: 1,
            timeBonus: 3 * 1e18,
            streakBonus: 1 * 1e18,
            enabled: true
        });
    }

    /**
     * @dev Creates or updates learner profile
     */
    function createLearnerProfile() external whenNotPaused {
        require(!learnerProfiles[msg.sender].isActive, "L2E: Profile already exists");
        
        learnerProfiles[msg.sender] = LearnerProfile({
            totalRewards: 0,
            modulesCompleted: 0,
            projectsSubmitted: 0,
            mentorshipSessions: 0,
            currentStreak: 0,
            longestStreak: 0,
            lastActivityTimestamp: 0,
            skillPoints: 0,
            isActive: true
        });
        
        emit LearnerProfileCreated(msg.sender);
    }

    /**
     * @dev Records a learning activity and distributes rewards
     * @param activityId Unique activity identifier
     * @param activityType Type of activity
     * @param skillCategory Skill category
     * @param skillLevel Skill level (1-10)
     * @param timeBonusEligible Whether learner completed within time limit
     * @return rewardAmount Total reward distributed
     */
    function recordActivity(
        bytes32 activityId,
        ActivityType activityType,
        string calldata skillCategory,
        uint256 skillLevel,
        bool timeBonusEligible
    ) external onlyRole(CURRICULUM_ROLE) whenNotPaused nonReentrant returns (uint256) {
        require(learnerProfiles[msg.sender].isActive, "L2E: Profile not active");
        require(!completedActivities[msg.sender][activityId], "L2E: Activity already completed");
        require(skillLevel >= 1 && skillLevel <= 10, "L2E: Invalid skill level");
        
        RewardConfig memory config = rewardConfigs[activityType];
        require(config.enabled, "L2E: Activity type disabled");
        
        // Calculate reward
        uint256 rewardAmount = _calculateReward(config, skillLevel, timeBonusEligible, msg.sender);
        
        // Update learner profile
        LearnerProfile storage profile = learnerProfiles[msg.sender];
        profile.totalRewards += rewardAmount;
        profile.skillPoints += skillLevel * 10;
        
        // Update activity-specific counters
        if (activityType == ActivityType.MODULE_COMPLETION) {
            profile.modulesCompleted++;
        } else if (activityType == ActivityType.PROJECT_SUBMISSION) {
            profile.projectsSubmitted++;
        } else if (activityType == ActivityType.PEER_MENTORSHIP) {
            profile.mentorshipSessions++;
        }
        
        // Update streak
        _updateStreak(msg.sender);
        
        // Mark activity as completed
        completedActivities[msg.sender][activityId] = true;
        
        // Store activity
        activities[activityId] = Activity({
            activityId: activityId,
            learner: msg.sender,
            activityType: activityType,
            skillCategory: skillCategory,
            skillLevel: skillLevel,
            completedAt: block.timestamp,
            rewardAmount: rewardAmount,
            verified: true,
            verifier: msg.sender
        });
        
        // Distribute rewards
        omniToken.mint(msg.sender, rewardAmount, "Learning Reward");
        
        // Check for skill milestone
        _checkSkillMilestone(msg.sender, skillCategory, skillLevel);
        
        emit ActivityCompleted(activityId, msg.sender, activityType, rewardAmount, skillCategory);
        emit RewardDistributed(msg.sender, rewardAmount, "Activity Completion");
        
        return rewardAmount;
    }

    /**
     * @dev Calculates reward amount based on configuration
     */
    function _calculateReward(
        RewardConfig memory config,
        uint256 skillLevel,
        bool timeBonusEligible,
        address learner
    ) internal view returns (uint256) {
        uint256 reward = config.baseReward;
        
        // Apply skill multiplier
        reward += (config.baseReward * config.skillMultiplier * skillLevel) / 100;
        
        // Apply time bonus
        if (timeBonusEligible) {
            reward += config.timeBonus;
        }
        
        // Apply streak bonus
        uint256 streak = learnerProfiles[learner].currentStreak;
        reward += config.streakBonus * streak;
        
        return reward;
    }

    /**
     * @dev Updates learner's activity streak
     */
    function _updateStreak(address learner) internal {
        LearnerProfile storage profile = learnerProfiles[learner];
        uint256 currentTime = block.timestamp;
        uint256 oneDay = 24 hours;
        
        if (profile.lastActivityTimestamp == 0) {
            // First activity
            profile.currentStreak = 1;
        } else if (currentTime - profile.lastActivityTimestamp <= oneDay) {
            // Within 24 hours, maintain or increase streak
            if (currentTime - profile.lastActivityTimestamp >= oneDay) {
                profile.currentStreak++;
            }
        } else {
            // Streak broken
            profile.currentStreak = 1;
        }
        
        profile.lastActivityTimestamp = currentTime;
        
        // Update longest streak
        if (profile.currentStreak > profile.longestStreak) {
            profile.longestStreak = profile.currentStreak;
        }
        
        emit StreakUpdated(learner, profile.currentStreak);
    }

    /**
     * @dev Checks if learner reached a skill milestone
     */
    function _checkSkillMilestone(address learner, string memory skillCategory, uint256 skillLevel) internal {
        // Issue SBT for skill milestones
        if (skillLevel == 5 || skillLevel == 10) {
            bytes32 proofHash = keccak256(abi.encodePacked(learner, skillCategory, skillLevel, block.timestamp));
            
            soulboundCredential.issueCredential(
                learner,
                SoulboundCredential.CredentialType.SKILL_ATTESTATION,
                skillCategory,
                skillLevel,
                0, // Non-expiring
                "", // Metadata URI can be set later
                proofHash
            );
            
            emit SkillMilestoneReached(learner, skillCategory, skillLevel);
        }
    }

    /**
     * @dev Updates reward configuration for an activity type
     * @param activityType Activity type to update
     * @param baseReward New base reward
     * @param skillMultiplier New skill multiplier
     * @param timeBonus New time bonus
     * @param streakBonus New streak bonus
     * @param enabled Whether activity is enabled
     */
    function updateRewardConfig(
        ActivityType activityType,
        uint256 baseReward,
        uint256 skillMultiplier,
        uint256 timeBonus,
        uint256 streakBonus,
        bool enabled
    ) external onlyRole(GOVERNANCE_ROLE) {
        rewardConfigs[activityType] = RewardConfig({
            baseReward: baseReward,
            skillMultiplier: skillMultiplier,
            timeBonus: timeBonus,
            streakBonus: streakBonus,
            enabled: enabled
        });
        
        emit RewardConfigUpdated(activityType, baseReward);
    }

    /**
     * @dev Gets learner profile
     * @param learner Address to check
     * @return Learner profile data
     */
    function getLearnerProfile(address learner) external view returns (LearnerProfile memory) {
        return learnerProfiles[learner];
    }

    /**
     * @dev Gets activity details
     * @param activityId Activity ID
     * @return Activity data
     */
    function getActivity(bytes32 activityId) external view returns (Activity memory) {
        return activities[activityId];
    }

    /**
     * @dev Checks if activity is completed by learner
     * @param learner Address to check
     * @param activityId Activity ID
     * @return Whether activity is completed
     */
    function isActivityCompleted(address learner, bytes32 activityId) external view returns (bool) {
        return completedActivities[learner][activityId];
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
