// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "../token/OMNIToken.sol";
import "../sbt/SoulboundCredential.sol";
import "../learn-to-earn/LearnToEarn.sol";

/**
 * @title GoMyCodeIntegration
 * @dev MAIN curriculum integration with GoMyCode
 * @notice GoMyCode is the PRIMARY curriculum provider:
 * - Syncs courses from GoMyCode platform
 * - Issues SBTs for GoMyCode certifications
 * - Rewards learning with $OMNI
 * - Tracks skill progression
 * - Connects graduates to jobs
 */
contract GoMyCodeIntegration is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant CURRICULUM_ROLE = keccak256("CURRICULUM_ROLE");
    bytes32 public constant INSTRUCTOR_ROLE = keccak256("INSTRUCTOR_ROLE");
    bytes32 public constant VERIFIER_ROLE = keccak256("VERIFIER_ROLE");
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");

    // Contract references
    OMNIToken public omniToken;
    SoulboundCredential public soulboundCredential;
    LearnToEarn public learnToEarn;

    // GoMyCode course structure
    struct GoMyCodeCourse {
        bytes32 courseId;
        string title;
        string description;
        string skillCategory;
        uint256 difficultyLevel; // 1-10
        uint256 estimatedDuration; // hours
        uint256 omniReward;
        string[] modules;
        string[] prerequisites;
        address instructor;
        bool isActive;
        uint256 enrollmentCount;
        uint256 completionCount;
        uint256 createdAt;
    }

    // Student enrollment
    struct Enrollment {
        bytes32 enrollmentId;
        address student;
        bytes32 courseId;
        uint256 enrolledAt;
        uint256 completedAt;
        uint256 progress; // 0-100
        uint256[] moduleScores;
        bool certified;
        bytes32 certificateId;
    }

    // GoMyCode certification
    struct GoMyCodeCertificate {
        bytes32 certificateId;
        address student;
        bytes32 courseId;
        string courseName;
        string skillCategory;
        uint256 skillLevel;
        uint256 issuedAt;
        string credentialURI;
        bytes32 verificationHash;
    }

    // Storage
    mapping(bytes32 => GoMyCodeCourse) public courses;
    mapping(bytes32 => Enrollment) public enrollments;
    mapping(bytes32 => GoMyCodeCertificate) public certificates;
    mapping(address => bytes32[]) public studentEnrollments;
    mapping(address => bytes32[]) public studentCertificates;
    mapping(bytes32 => bool) public usedVerificationHashes;
    
    // GoMyCode API integration
    mapping(address => bool) public authorizedInstructors;
    mapping(bytes32 => address) public courseInstructors;
    
    // Statistics
    uint256 public totalCourses;
    uint256 public totalEnrollments;
    uint256 public totalCertifications;
    uint256 public totalOmniDistributed;

    // Events
    event CourseCreated(bytes32 indexed courseId, string title, address instructor);
    event CourseUpdated(bytes32 indexed courseId, string title);
    event StudentEnrolled(bytes32 indexed enrollmentId, address indexed student, bytes32 indexed courseId);
    event ModuleCompleted(bytes32 indexed enrollmentId, uint256 moduleIndex, uint256 score);
    event CourseCompleted(bytes32 indexed enrollmentId, address indexed student, bytes32 indexed courseId);
    event CertificateIssued(bytes32 indexed certificateId, address indexed student, bytes32 indexed courseId);
    event OmniRewarded(address indexed student, uint256 amount, string reason);
    event InstructorAuthorized(address indexed instructor);
    event InstructorRevoked(address indexed instructor);

    /**
     * @dev Constructor initializes GoMyCode integration
     * @param _omniToken Address of OMNI token contract
     * @param _soulboundCredential Address of SBT contract
     * @param _learnToEarn Address of Learn-to-Earn contract
     */
    constructor(
        address _omniToken,
        address _soulboundCredential,
        address _learnToEarn
    ) {
        require(_omniToken != address(0), "GoMyCode: Invalid token address");
        require(_soulboundCredential != address(0), "GoMyCode: Invalid SBT address");
        require(_learnToEarn != address(0), "GoMyCode: Invalid L2E address");
        
        omniToken = OMNIToken(_omniToken);
        soulboundCredential = SoulboundCredential(_soulboundCredential);
        learnToEarn = LearnToEarn(_learnToEarn);
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(CURRICULUM_ROLE, msg.sender);
        _grantRole(INSTRUCTOR_ROLE, msg.sender);
        _grantRole(VERIFIER_ROLE, msg.sender);
        _grantRole(GOVERNANCE_ROLE, msg.sender);
    }

    /**
     * @dev Creates a new GoMyCode course
     * @param title Course title
     * @param description Course description
     * @param skillCategory Skill category
     * @param difficultyLevel Difficulty level (1-10)
     * @param estimatedDuration Estimated duration in hours
     * @param omniReward OMNI reward for completion
     * @param modules Array of module names
     * @param prerequisites Array of prerequisite course IDs
     * @return courseId Created course ID
     */
    function createCourse(
        string calldata title,
        string calldata description,
        string calldata skillCategory,
        uint256 difficultyLevel,
        uint256 estimatedDuration,
        uint256 omniReward,
        string[] calldata modules,
        string[] calldata prerequisites
    ) external onlyRole(CURRICULUM_ROLE) returns (bytes32) {
        require(bytes(title).length > 0, "GoMyCode: Empty title");
        require(difficultyLevel >= 1 && difficultyLevel <= 10, "GoMyCode: Invalid difficulty");
        require(modules.length > 0, "GoMyCode: No modules");
        
        bytes32 courseId = keccak256(abi.encodePacked(title, block.timestamp));
        
        courses[courseId] = GoMyCodeCourse({
            courseId: courseId,
            title: title,
            description: description,
            skillCategory: skillCategory,
            difficultyLevel: difficultyLevel,
            estimatedDuration: estimatedDuration,
            omniReward: omniReward,
            modules: modules,
            prerequisites: prerequisites,
            instructor: msg.sender,
            isActive: true,
            enrollmentCount: 0,
            completionCount: 0,
            createdAt: block.timestamp
        });
        
        courseInstructors[courseId] = msg.sender;
        totalCourses++;
        
        emit CourseCreated(courseId, title, msg.sender);
        
        return courseId;
    }

    /**
     * @dev Enrolls student in GoMyCode course
     * @param courseId Course ID
     * @return enrollmentId Enrollment ID
     */
    function enrollInCourse(bytes32 courseId) external whenNotPaused returns (bytes32) {
        GoMyCodeCourse storage course = courses[courseId];
        require(course.isActive, "GoMyCode: Course not active");
        
        // Check prerequisites
        for (uint256 i = 0; i < course.prerequisites.length; i++) {
            bytes32 prereqId = bytes32(bytes(course.prerequisites[i]));
            require(_hasCompletedCourse(msg.sender, prereqId), "GoMyCode: Prerequisites not met");
        }
        
        bytes32 enrollmentId = keccak256(abi.encodePacked(msg.sender, courseId, block.timestamp));
        
        enrollments[enrollmentId] = Enrollment({
            enrollmentId: enrollmentId,
            student: msg.sender,
            courseId: courseId,
            enrolledAt: block.timestamp,
            completedAt: 0,
            progress: 0,
            moduleScores: new uint256[](course.modules.length),
            certified: false,
            certificateId: bytes32(0)
        });
        
        studentEnrollments[msg.sender].push(enrollmentId);
        course.enrollmentCount++;
        totalEnrollments++;
        
        emit StudentEnrolled(enrollmentId, msg.sender, courseId);
        
        return enrollmentId;
    }

    /**
     * @dev Records module completion
     * @param enrollmentId Enrollment ID
     * @param moduleIndex Module index
     * @param score Module score (0-100)
     */
    function completeModule(
        bytes32 enrollmentId,
        uint256 moduleIndex,
        uint256 score
    ) external onlyRole(VERIFIER_ROLE) {
        Enrollment storage enrollment = enrollments[enrollmentId];
        require(enrollment.student != address(0), "GoMyCode: Invalid enrollment");
        require(!enrollment.certified, "GoMyCode: Already certified");
        require(score <= 100, "GoMyCode: Invalid score");
        
        GoMyCodeCourse storage course = courses[enrollment.courseId];
        require(moduleIndex < course.modules.length, "GoMyCode: Invalid module");
        
        enrollment.moduleScores[moduleIndex] = score;
        
        // Calculate progress
        uint256 completedModules = 0;
        for (uint256 i = 0; i < enrollment.moduleScores.length; i++) {
            if (enrollment.moduleScores[i] > 0) {
                completedModules++;
            }
        }
        enrollment.progress = (completedModules * 100) / course.modules.length;
        
        emit ModuleCompleted(enrollmentId, moduleIndex, score);
        
        // Check if course completed
        if (enrollment.progress == 100) {
            _completeCourse(enrollmentId);
        }
    }

    /**
     * @dev Completes course and issues certificate
     * @param enrollmentId Enrollment ID
     */
    function _completeCourse(bytes32 enrollmentId) internal {
        Enrollment storage enrollment = enrollments[enrollmentId];
        GoMyCodeCourse storage course = courses[enrollment.courseId];
        
        enrollment.completedAt = block.timestamp;
        course.completionCount++;
        
        // Calculate average score
        uint256 totalScore = 0;
        for (uint256 i = 0; i < enrollment.moduleScores.length; i++) {
            totalScore += enrollment.moduleScores[i];
        }
        uint256 avgScore = totalScore / enrollment.moduleScores.length;
        
        // Issue certificate
        bytes32 certificateId = _issueCertificate(
            enrollment.student,
            enrollment.courseId,
            course.title,
            course.skillCategory,
            course.difficultyLevel,
            avgScore
        );
        
        enrollment.certified = true;
        enrollment.certificateId = certificateId;
        
        // Reward with OMNI
        uint256 reward = course.omniReward;
        omniToken.mint(enrollment.student, reward, "GoMyCode Course Completion");
        totalOmniDistributed += reward;
        
        // Record in Learn-to-Earn
        bytes32 activityId = keccak256(abi.encodePacked(enrollment.student, enrollment.courseId, "completion"));
        learnToEarn.recordActivity(
            activityId,
            LearnToEarn.ActivityType.PROJECT_SUBMISSION,
            course.skillCategory,
            course.difficultyLevel,
            true
        );
        
        emit CourseCompleted(enrollmentId, enrollment.student, enrollment.courseId);
        emit OmniRewarded(enrollment.student, reward, "GoMyCode Course Completion");
    }

    /**
     * @dev Issues GoMyCode certificate (SBT)
     * @param student Student address
     * @param courseId Course ID
     * @param courseName Course name
     * @param skillCategory Skill category
     * @param skillLevel Skill level
     * @param avgScore Average score
     * @return certificateId Certificate ID
     */
    function _issueCertificate(
        address student,
        bytes32 courseId,
        string memory courseName,
        string memory skillCategory,
        uint256 skillLevel,
        uint256 avgScore
    ) internal returns (bytes32) {
        bytes32 certificateId = keccak256(abi.encodePacked(student, courseId, block.timestamp));
        
        // Generate verification hash
        bytes32 verificationHash = keccak256(abi.encodePacked(
            student,
            courseId,
            courseName,
            skillLevel,
            avgScore,
            block.timestamp
        ));
        
        require(!usedVerificationHashes[verificationHash], "GoMyCode: Hash already used");
        usedVerificationHashes[verificationHash] = true;
        
        // Store certificate
        certificates[certificateId] = GoMyCodeCertificate({
            certificateId: certificateId,
            student: student,
            courseId: courseId,
            courseName: courseName,
            skillCategory: skillCategory,
            skillLevel: skillLevel,
            issuedAt: block.timestamp,
            credentialURI: "",
            verificationHash: verificationHash
        });
        
        studentCertificates[student].push(certificateId);
        totalCertifications++;
        
        // Issue SBT
        soulboundCredential.issueCredential(
            student,
            SoulboundCredential.CredentialType.COURSE_COMPLETION,
            skillCategory,
            skillLevel,
            0, // Non-expiring
            "", // Metadata URI
            verificationHash
        );
        
        emit CertificateIssued(certificateId, student, courseId);
        
        return certificateId;
    }

    /**
     * @dev Checks if student has completed a course
     * @param student Student address
     * @param courseId Course ID
     * @return Whether course is completed
     */
    function _hasCompletedCourse(address student, bytes32 courseId) internal view returns (bool) {
        bytes32[] memory enrollments = studentEnrollments[student];
        
        for (uint256 i = 0; i < enrollments.length; i++) {
            Enrollment storage enrollment = enrollments[enrollments[i]];
            if (enrollment.courseId == courseId && enrollment.certified) {
                return true;
            }
        }
        
        return false;
    }

    /**
     * @dev Authorizes an instructor
     * @param instructor Instructor address
     */
    function authorizeInstructor(address instructor) external onlyRole(GOVERNANCE_ROLE) {
        authorizedInstructors[instructor] = true;
        _grantRole(INSTRUCTOR_ROLE, instructor);
        emit InstructorAuthorized(instructor);
    }

    /**
     * @dev Revokes an instructor
     * @param instructor Instructor address
     */
    function revokeInstructor(address instructor) external onlyRole(GOVERNANCE_ROLE) {
        authorizedInstructors[instructor] = false;
        _revokeRole(INSTRUCTOR_ROLE, instructor);
        emit InstructorRevoked(instructor);
    }

    /**
     * @dev Gets course details
     * @param courseId Course ID
     * @return GoMyCodeCourse data
     */
    function getCourse(bytes32 courseId) external view returns (GoMyCodeCourse memory) {
        return courses[courseId];
    }

    /**
     * @dev Gets enrollment details
     * @param enrollmentId Enrollment ID
     * @return Enrollment data
     */
    function getEnrollment(bytes32 enrollmentId) external view returns (Enrollment memory) {
        return enrollments[enrollmentId];
    }

    /**
     * @dev Gets certificate details
     * @param certificateId Certificate ID
     * @return GoMyCodeCertificate data
     */
    function getCertificate(bytes32 certificateId) external view returns (GoMyCodeCertificate memory) {
        return certificates[certificateId];
    }

    /**
     * @dev Gets student's enrollments
     * @param student Student address
     * @return Array of enrollment IDs
     */
    function getStudentEnrollments(address student) external view returns (bytes32[] memory) {
        return studentEnrollments[student];
    }

    /**
     * @dev Gets student's certificates
     * @param student Student address
     * @return Array of certificate IDs
     */
    function getStudentCertificates(address student) external view returns (bytes32[] memory) {
        return studentCertificates[student];
    }

    /**
     * @dev Gets all active courses
     * @return Array of course IDs
     */
    function getActiveCourses() external view returns (bytes32[] memory) {
        // In production, maintain a list of active courses
        // For now, return empty array
        return new bytes32[](0);
    }

    /**
     * @dev Updates course
     * @param courseId Course ID
     * @param title New title
     * @param description New description
     */
    function updateCourse(
        bytes32 courseId,
        string calldata title,
        string calldata description
    ) external {
        GoMyCodeCourse storage course = courses[courseId];
        require(msg.sender == course.instructor || hasRole(GOVERNANCE_ROLE, msg.sender), 
            "GoMyCode: Not authorized");
        
        course.title = title;
        course.description = description;
        
        emit CourseUpdated(courseId, title);
    }

    /**
     * @dev Deactivates course
     * @param courseId Course ID
     */
    function deactivateCourse(bytes32 courseId) external {
        GoMyCodeCourse storage course = courses[courseId];
        require(msg.sender == course.instructor || hasRole(GOVERNANCE_ROLE, msg.sender), 
            "GoMyCode: Not authorized");
        
        course.isActive = false;
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
