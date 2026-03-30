// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "../token/OMNIToken.sol";

/**
 * @title MPesaBridge
 * @dev Bridge for M-Pesa integration
 * @notice Handles:
 * - OMNI to KES conversions
 * - KES to OMNI conversions
 * - USSD integration
 * - Mobile money transfers
 * - Oracle price feeds
 */
contract MPesaBridge is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");

    // Contract references
    OMNIToken public omniToken;

    // Conversion rates
    uint256 public omniToKesRate; // 1 OMNI = X KES (in cents)
    uint256 public kesToOmniRate; // 100 KES = X OMNI (in wei)
    uint256 public lastRateUpdate;
    
    // Fees
    uint256 public constant CONVERSION_FEE = 100; // 1% in basis points
    uint256 public constant USSD_FEE = 10; // 0.1% in basis points
    uint256 public constant FEE_DENOMINATOR = 10000;
    
    // Limits
    uint256 public dailyConversionLimit = 100000 * 1e18; // 100k OMNI per day
    uint256 public minConversionAmount = 10 * 1e18; // 10 OMNI minimum
    uint256 public maxConversionAmount = 10000 * 1e18; // 10k OMNI maximum
    
    // Daily tracking
    mapping(address => uint256) public dailyConversions;
    mapping(address => uint256) public lastConversionDay;
    
    // Pending conversions
    mapping(bytes32 => ConversionRequest) public pendingConversions;
    mapping(address => bytes32[]) public userConversions;
    
    // USSD sessions
    mapping(bytes32 => USSDSession) public ussdSessions;
    
    // Structs
    struct ConversionRequest {
        bytes32 requestId;
        address user;
        uint256 omniAmount;
        uint256 kesAmount;
        uint256 fee;
        ConversionType conversionType;
        uint256 timestamp;
        bool completed;
        bool cancelled;
        string mpesaReference;
    }
    
    struct USSDSession {
        bytes32 sessionId;
        address user;
        string phoneNumber;
        uint256 step;
        uint256 createdAt;
        bool active;
        string lastInput;
    }
    
    enum ConversionType {
        OMNI_TO_KES,
        KES_TO_OMNI
    }
    
    // Events
    event ConversionInitiated(
        bytes32 indexed requestId,
        address indexed user,
        uint256 omniAmount,
        uint256 kesAmount,
        ConversionType conversionType
    );
    event ConversionCompleted(
        bytes32 indexed requestId,
        address indexed user,
        uint256 amount,
        string mpesaReference
    );
    event ConversionCancelled(bytes32 indexed requestId, address indexed user);
    event RateUpdated(uint256 omniToKes, uint256 kesToOmni);
    event USSDSessionStarted(bytes32 indexed sessionId, address indexed user, string phoneNumber);
    event USSDSessionEnded(bytes32 indexed sessionId, address indexed user);
    event DailyLimitReset(address indexed user);
    event FeesCollected(address indexed from, uint256 omniFee, uint256 kesFee);

    /**
     * @dev Constructor initializes the M-Pesa bridge
     * @param _omniToken Address of OMNI token contract
     */
    constructor(address _omniToken) {
        require(_omniToken != address(0), "Bridge: Invalid token address");
        
        omniToken = OMNIToken(_omniToken);
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ORACLE_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
        _grantRole(GOVERNANCE_ROLE, msg.sender);
        
        // Initialize with default rate (1 OMNI = 100 KES)
        omniToKesRate = 10000; // 100.00 KES (in cents)
        kesToOmniRate = 1e16; // 0.01 OMNI per 100 KES
        lastRateUpdate = block.timestamp;
    }

    /**
     * @dev Initiates OMNI to KES conversion
     * @param omniAmount Amount of OMNI to convert
     * @param phoneNumber M-Pesa phone number
     * @return requestId Conversion request ID
     */
    function initiateOMNItoKES(
        uint256 omniAmount,
        string calldata phoneNumber
    ) external whenNotPaused nonReentrant returns (bytes32) {
        require(omniAmount >= minConversionAmount, "Bridge: Below minimum");
        require(omniAmount <= maxConversionAmount, "Bridge: Above maximum");
        require(omniToken.balanceOf(msg.sender) >= omniAmount, "Bridge: Insufficient balance");
        
        // Check daily limit
        _checkDailyLimit(msg.sender, omniAmount);
        
        // Calculate KES amount and fee
        uint256 kesAmount = (omniAmount * omniToKesRate) / 1e18;
        uint256 fee = (omniAmount * CONVERSION_FEE) / FEE_DENOMINATOR;
        uint256 netOmniAmount = omniAmount - fee;
        
        // Generate request ID
        bytes32 requestId = keccak256(abi.encodePacked(msg.sender, omniAmount, block.timestamp, phoneNumber));
        
        // Store conversion request
        pendingConversions[requestId] = ConversionRequest({
            requestId: requestId,
            user: msg.sender,
            omniAmount: netOmniAmount,
            kesAmount: kesAmount,
            fee: fee,
            conversionType: ConversionType.OMNI_TO_KES,
            timestamp: block.timestamp,
            completed: false,
            cancelled: false,
            mpesaReference: ""
        });
        
        userConversions[msg.sender].push(requestId);
        
        // Burn OMNI tokens
        omniToken.burn(netOmniAmount);
        
        // Update daily tracking
        dailyConversions[msg.sender] += omniAmount;
        lastConversionDay[msg.sender] = block.timestamp / 1 days;
        
        emit ConversionInitiated(requestId, msg.sender, netOmniAmount, kesAmount, ConversionType.OMNI_TO_KES);
        
        return requestId;
    }

    /**
     * @dev Initiates KES to OMNI conversion
     * @param kesAmount Amount of KES to convert
     * @param phoneNumber M-Pesa phone number
     * @return requestId Conversion request ID
     */
    function initiateKEStoOMNI(
        uint256 kesAmount,
        string calldata phoneNumber
    ) external whenNotPaused nonReentrant returns (bytes32) {
        require(kesAmount >= 1000, "Bridge: Below minimum (10 KES)");
        
        // Calculate OMNI amount and fee
        uint256 omniAmount = (kesAmount * kesToOmniRate) / 1e18;
        uint256 fee = (omniAmount * CONVERSION_FEE) / FEE_DENOMINATOR;
        uint256 netOmniAmount = omniAmount - fee;
        
        // Generate request ID
        bytes32 requestId = keccak256(abi.encodePacked(msg.sender, kesAmount, block.timestamp, phoneNumber));
        
        // Store conversion request
        pendingConversions[requestId] = ConversionRequest({
            requestId: requestId,
            user: msg.sender,
            omniAmount: netOmniAmount,
            kesAmount: kesAmount,
            fee: fee,
            conversionType: ConversionType.KES_TO_OMNI,
            timestamp: block.timestamp,
            completed: false,
            cancelled: false,
            mpesaReference: ""
        });
        
        userConversions[msg.sender].push(requestId);
        
        emit ConversionInitiated(requestId, msg.sender, netOmniAmount, kesAmount, ConversionType.KES_TO_OMNI);
        
        return requestId;
    }

    /**
     * @dev Completes a conversion (called by oracle/operator)
     * @param requestId Conversion request ID
     * @param mpesaReference M-Pesa transaction reference
     */
    function completeConversion(
        bytes32 requestId,
        string calldata mpesaReference
    ) external onlyRole(OPERATOR_ROLE) nonReentrant {
        ConversionRequest storage request = pendingConversions[requestId];
        require(!request.completed && !request.cancelled, "Bridge: Already processed");
        
        if (request.conversionType == ConversionType.KES_TO_OMNI) {
            // Mint OMNI to user
            omniToken.mint(request.user, request.omniAmount, "M-Pesa Conversion");
        }
        
        request.completed = true;
        request.mpesaReference = mpesaReference;
        
        emit ConversionCompleted(requestId, request.user, request.omniAmount, mpesaReference);
    }

    /**
     * @dev Cancels a conversion
     * @param requestId Conversion request ID
     */
    function cancelConversion(bytes32 requestId) external {
        ConversionRequest storage request = pendingConversions[requestId];
        require(msg.sender == request.user || hasRole(OPERATOR_ROLE, msg.sender), "Bridge: Not authorized");
        require(!request.completed && !request.cancelled, "Bridge: Already processed");
        
        if (request.conversionType == ConversionType.OMNI_TO_KES) {
            // Refund OMNI to user
            omniToken.mint(request.user, request.omniAmount + request.fee, "Conversion Refund");
        }
        
        request.cancelled = true;
        
        emit ConversionCancelled(requestId, request.user);
    }

    /**
     * @dev Starts a USSD session
     * @param phoneNumber User's phone number
     * @return sessionId USSD session ID
     */
    function startUSSDSession(string calldata phoneNumber) external returns (bytes32) {
        bytes32 sessionId = keccak256(abi.encodePacked(msg.sender, phoneNumber, block.timestamp));
        
        ussdSessions[sessionId] = USSDSession({
            sessionId: sessionId,
            user: msg.sender,
            phoneNumber: phoneNumber,
            step: 0,
            createdAt: block.timestamp,
            active: true,
            lastInput: ""
        });
        
        emit USSDSessionStarted(sessionId, msg.sender, phoneNumber);
        
        return sessionId;
    }

    /**
     * @dev Processes USSD input
     * @param sessionId USSD session ID
     * @param input User input
     * @return response USSD response
     */
    function processUSSDInput(bytes32 sessionId, string calldata input) 
        external 
        onlyRole(OPERATOR_ROLE) 
        returns (string memory) 
    {
        USSDSession storage session = ussdSessions[sessionId];
        require(session.active, "Bridge: Session not active");
        require(block.timestamp - session.createdAt <= 5 minutes, "Bridge: Session expired");
        
        session.lastInput = input;
        
        // USSD menu logic
        if (session.step == 0) {
            // Main menu
            session.step = 1;
            return "Welcome to Omniversity\n1. Check Balance\n2. Convert OMNI to KES\n3. Convert KES to OMNI\n4. Exit";
        } else if (session.step == 1) {
            // Process selection
            if (keccak256(bytes(input)) == keccak256(bytes("1"))) {
                uint256 balance = omniToken.balanceOf(session.user);
                return string(abi.encodePacked("Your OMNI balance: ", _uintToString(balance / 1e18), " OMNI"));
            } else if (keccak256(bytes(input)) == keccak256(bytes("2"))) {
                session.step = 2;
                return "Enter OMNI amount to convert:";
            } else if (keccak256(bytes(input)) == keccak256(bytes("3"))) {
                session.step = 3;
                return "Enter KES amount to convert:";
            } else if (keccak256(bytes(input)) == keccak256(bytes("4"))) {
                session.active = false;
                emit USSDSessionEnded(sessionId, session.user);
                return "Thank you for using Omniversity!";
            }
        } else if (session.step == 2) {
            // OMNI to KES conversion
            uint256 amount = _stringToUint(input);
            if (amount >= minConversionAmount / 1e18 && amount <= maxConversionAmount / 1e18) {
                session.active = false;
                emit USSDSessionEnded(sessionId, session.user);
                return string(abi.encodePacked("Conversion initiated. You will receive ", _uintToString((amount * omniToKesRate) / 100), " KES"));
            }
        } else if (session.step == 3) {
            // KES to OMNI conversion
            uint256 amount = _stringToUint(input);
            if (amount >= 10) {
                session.active = false;
                emit USSDSessionEnded(sessionId, session.user);
                return string(abi.encodePacked("Conversion initiated. You will receive ", _uintToString((amount * kesToOmniRate) / 1e18), " OMNI"));
            }
        }
        
        return "Invalid input. Please try again.";
    }

    /**
     * @dev Updates conversion rates (called by oracle)
     * @param newOmniToKes New OMNI to KES rate
     * @param newKesToOmni New KES to OMNI rate
     */
    function updateRates(uint256 newOmniToKes, uint256 newKesToOmni) external onlyRole(ORACLE_ROLE) {
        require(newOmniToKes > 0 && newKesToOmni > 0, "Bridge: Invalid rates");
        
        omniToKesRate = newOmniToKes;
        kesToOmniRate = newKesToOmni;
        lastRateUpdate = block.timestamp;
        
        emit RateUpdated(newOmniToKes, newKesToOmni);
    }

    /**
     * @dev Checks daily conversion limit
     * @param user User address
     * @param amount Conversion amount
     */
    function _checkDailyLimit(address user, uint256 amount) internal {
        uint256 currentDay = block.timestamp / 1 days;
        
        if (lastConversionDay[user] != currentDay) {
            dailyConversions[user] = 0;
            lastConversionDay[user] = currentDay;
            emit DailyLimitReset(user);
        }
        
        require(dailyConversions[user] + amount <= dailyConversionLimit, "Bridge: Daily limit exceeded");
    }

    /**
     * @dev Converts uint to string
     * @param value Value to convert
     * @return String representation
     */
    function _uintToString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        
        uint256 temp = value;
        uint256 digits;
        
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        
        bytes memory buffer = new bytes(digits);
        
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + (value % 10)));
            value /= 10;
        }
        
        return string(buffer);
    }

    /**
     * @dev Converts string to uint
     * @param str String to convert
     * @return Uint value
     */
    function _stringToUint(string memory str) internal pure returns (uint256) {
        bytes memory b = bytes(str);
        uint256 result = 0;
        
        for (uint256 i = 0; i < b.length; i++) {
            if (uint8(b[i]) >= 48 && uint8(b[i]) <= 57) {
                result = result * 10 + (uint8(b[i]) - 48);
            }
        }
        
        return result;
    }

    /**
     * @dev Gets conversion request details
     * @param requestId Request ID
     * @return ConversionRequest data
     */
    function getConversionRequest(bytes32 requestId) external view returns (ConversionRequest memory) {
        return pendingConversions[requestId];
    }

    /**
     * @dev Gets user's conversion requests
     * @param user User address
     * @return Array of request IDs
     */
    function getUserConversions(address user) external view returns (bytes32[] memory) {
        return userConversions[user];
    }

    /**
     * @dev Gets USSD session details
     * @param sessionId Session ID
     * @return USSDSession data
     */
    function getUSSDSession(bytes32 sessionId) external view returns (USSDSession memory) {
        return ussdSessions[sessionId];
    }

    /**
     * @dev Updates daily conversion limit
     * @param newLimit New limit in OMNI
     */
    function updateDailyLimit(uint256 newLimit) external onlyRole(GOVERNANCE_ROLE) {
        dailyConversionLimit = newLimit;
    }

    /**
     * @dev Updates minimum conversion amount
     * @param newMinimum New minimum in OMNI
     */
    function updateMinConversion(uint256 newMinimum) external onlyRole(GOVERNANCE_ROLE) {
        minConversionAmount = newMinimum;
    }

    /**
     * @dev Updates maximum conversion amount
     * @param newMaximum New maximum in OMNI
     */
    function updateMaxConversion(uint256 newMaximum) external onlyRole(GOVERNANCE_ROLE) {
        maxConversionAmount = newMaximum;
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
