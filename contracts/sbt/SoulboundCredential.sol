// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title SoulboundCredential
 * @dev Soulbound Tokens (SBTs) for non-transferable credentials
 * @notice SBTs represent:
 * - Course completion certificates
 * - Skill attestations
 * - Guild memberships
 * - Achievement badges
 * - Mentorship certifications
 */
contract SoulboundCredential is ERC721, ERC721URIStorage, AccessControl, ReentrancyGuard {
    using Counters for Counters.Counter;

    bytes32 public constant ISSUER_ROLE = keccak256("ISSUER_ROLE");
    bytes32 public constant VERIFIER_ROLE = keccak256("VERIFIER_ROLE");
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");

    Counters.Counter private _tokenIds;

    // Credential types
    enum CredentialType {
        COURSE_COMPLETION,
        SKILL_ATTESTATION,
        GUILD_MEMBERSHIP,
        ACHIEVEMENT_BADGE,
        MENTORSHIP_CERTIFICATION,
        PEER_REVIEW,
        PROJECT_COMPLETION
    }

    // Credential metadata
    struct Credential {
        uint256 tokenId;
        address recipient;
        CredentialType credentialType;
        string skillCategory;
        uint256 skillLevel; // 1-10 scale
        uint256 issuedAt;
        uint256 expiresAt; // 0 for non-expiring
        address issuer;
        string metadataURI;
        bool revoked;
        bytes32 proofHash; // Hash of verification proof
    }

    // Storage
    mapping(uint256 => Credential) public credentials;
    mapping(address => uint256[]) public userCredentials;
    mapping(address => mapping(CredentialType => uint256)) public credentialCount;
    mapping(bytes32 => bool) public usedProofs;

    // Skill graph
    mapping(address => mapping(string => uint256)) public skillLevels;
    mapping(address => string[]) public userSkills;

    // Events
    event CredentialIssued(
        uint256 indexed tokenId,
        address indexed recipient,
        CredentialType credentialType,
        string skillCategory,
        uint256 skillLevel,
        address indexed issuer
    );
    event CredentialRevoked(uint256 indexed tokenId, address indexed revoker);
    event SkillLevelUpdated(address indexed user, string skill, uint256 newLevel);
    event CredentialTransferred(address indexed from, address indexed to, uint256 indexed tokenId);

    /**
     * @dev Constructor initializes the SBT contract
     */
    constructor() ERC721("Omniversity Credential", "OMNI-CRED") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ISSUER_ROLE, msg.sender);
        _grantRole(VERIFIER_ROLE, msg.sender);
        _grantRole(GOVERNANCE_ROLE, msg.sender);
    }

    /**
     * @dev Issues a new soulbound credential
     * @param recipient Address receiving the credential
     * @param credentialType Type of credential
     * @param skillCategory Skill category (e.g., "Web Development", "Blockchain")
     * @param skillLevel Skill level (1-10)
     * @param expiresAt Expiration timestamp (0 for non-expiring)
     * @param metadataURI URI for credential metadata
     * @param proofHash Hash of verification proof
     * @return tokenId The issued token ID
     */
    function issueCredential(
        address recipient,
        CredentialType credentialType,
        string calldata skillCategory,
        uint256 skillLevel,
        uint256 expiresAt,
        string calldata metadataURI,
        bytes32 proofHash
    ) external onlyRole(ISSUER_ROLE) nonReentrant returns (uint256) {
        require(recipient != address(0), "SBT: Cannot issue to zero address");
        require(skillLevel >= 1 && skillLevel <= 10, "SBT: Invalid skill level");
        require(!usedProofs[proofHash], "SBT: Proof already used");
        
        _tokenIds.increment();
        uint256 newTokenId = _tokenIds.current();
        
        // Mint the SBT (non-transferable by default)
        _safeMint(recipient, newTokenId);
        _setTokenURI(newTokenId, metadataURI);
        
        // Store credential data
        credentials[newTokenId] = Credential({
            tokenId: newTokenId,
            recipient: recipient,
            credentialType: credentialType,
            skillCategory: skillCategory,
            skillLevel: skillLevel,
            issuedAt: block.timestamp,
            expiresAt: expiresAt,
            issuer: msg.sender,
            metadataURI: metadataURI,
            revoked: false,
            proofHash: proofHash
        });
        
        // Update user credentials
        userCredentials[recipient].push(newTokenId);
        credentialCount[recipient][credentialType]++;
        
        // Mark proof as used
        usedProofs[proofHash] = true;
        
        // Update skill levels
        _updateSkillLevel(recipient, skillCategory, skillLevel);
        
        emit CredentialIssued(
            newTokenId,
            recipient,
            credentialType,
            skillCategory,
            skillLevel,
            msg.sender
        );
        
        return newTokenId;
    }

    /**
     * @dev Revokes a credential
     * @param tokenId Token ID to revoke
     */
    function revokeCredential(uint256 tokenId) external onlyRole(ISSUER_ROLE) {
        require(_exists(tokenId), "SBT: Token does not exist");
        require(!credentials[tokenId].revoked, "SBT: Already revoked");
        
        credentials[tokenId].revoked = true;
        
        emit CredentialRevoked(tokenId, msg.sender);
    }

    /**
     * @dev Verifies a credential's validity
     * @param tokenId Token ID to verify
     * @return isValid Whether the credential is valid
     * @return credential The credential data
     */
    function verifyCredential(uint256 tokenId) 
        external 
        view 
        returns (bool isValid, Credential memory credential) 
    {
        require(_exists(tokenId), "SBT: Token does not exist");
        
        credential = credentials[tokenId];
        
        // Check if revoked
        if (credential.revoked) {
            return (false, credential);
        }
        
        // Check if expired
        if (credential.expiresAt > 0 && block.timestamp > credential.expiresAt) {
            return (false, credential);
        }
        
        return (true, credential);
    }

    /**
     * @dev Gets all credentials for a user
     * @param user Address to check
     * @return Array of token IDs
     */
    function getUserCredentials(address user) external view returns (uint256[] memory) {
        return userCredentials[user];
    }

    /**
     * @dev Gets user's skill level in a category
     * @param user Address to check
     * @param skillCategory Skill category
     * @return Skill level
     */
    function getSkillLevel(address user, string calldata skillCategory) 
        external 
        view 
        returns (uint256) 
    {
        return skillLevels[user][skillCategory];
    }

    /**
     * @dev Gets all skills for a user
     * @param user Address to check
     * @return Array of skill categories
     */
    function getUserSkills(address user) external view returns (string[] memory) {
        return userSkills[user];
    }

    /**
     * @dev Updates skill level for a user
     * @param user Address to update
     * @param skillCategory Skill category
     * @param newLevel New skill level
     */
    function _updateSkillLevel(address user, string memory skillCategory, uint256 newLevel) internal {
        uint256 oldLevel = skillLevels[user][skillCategory];
        
        if (newLevel > oldLevel) {
            skillLevels[user][skillCategory] = newLevel;
            
            // Add to user skills if new
            if (oldLevel == 0) {
                userSkills[user].push(skillCategory);
            }
            
            emit SkillLevelUpdated(user, skillCategory, newLevel);
        }
    }

    /**
     * @dev Checks if user has a specific credential type
     * @param user Address to check
     * @param credentialType Type to check
     * @return hasCredential Whether user has the credential
     */
    function hasCredentialType(address user, CredentialType credentialType) 
        external 
        view 
        returns (bool) 
    {
        return credentialCount[user][credentialType] > 0;
    }

    /**
     * @dev Gets credential count by type for a user
     * @param user Address to check
     * @param credentialType Type to check
     * @return count Number of credentials of that type
     */
    function getCredentialCount(address user, CredentialType credentialType) 
        external 
        view 
        returns (uint256) 
    {
        return credentialCount[user][credentialType];
    }

    /**
     * @dev Prevents transfer (soulbound)
     */
    function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize)
        internal
        override(ERC721)
    {
        // Allow minting (from == address(0)) but prevent transfers
        require(from == address(0) || to == address(0), "SBT: Soulbound tokens are non-transferable");
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    /**
     * @dev Override tokenURI to use ERC721URIStorage
     */
    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    /**
     * @dev Override supportsInterface
     */
    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721URIStorage, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
