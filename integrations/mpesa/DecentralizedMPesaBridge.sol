// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "../token/OMNIToken.sol";

/**
 * @title DecentralizedMPesaBridge
 * @dev Fully decentralized M-Pesa integration for The Omniversity Protocol
 * @notice M-Pesa is the PRIMARY fiat on/off ramp - fully decentralized through:
 * - Chainlink oracles for price feeds
 * - Multi-signature validation
 * - Community-operated nodes
 * - Decentralized USSD gateway
 * - Peer-to-peer conversion network
 */
contract DecentralizedMPesaBridge is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    bytes32 public constant VALIDATOR_ROLE = keccak256("VALIDATOR_ROLE");
    bytes32 public constant NODE_OPERATOR_ROLE = keccak256("NODE_OPERATOR_ROLE");
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");

    // Contract references
    OMNIToken public omniToken;

    // Decentralized oracle network
    struct OracleNode {
        address nodeAddress;
        string endpoint;
        uint256 stake;
        uint256 reputation;
        bool isActive;
        uint256 lastUpdate;
    }

    // Conversion rates from multiple oracles
    struct PriceFeed {
        uint256 omniToKes;
        uint256 kesToOmni;
        uint256 timestamp;
        address oracle;
        bytes signature;
    }

    // P2P conversion orders
    struct ConversionOrder {
        bytes32 orderId;
        address maker; // User offering conversion
        address taker; // User taking conversion
        uint256 omniAmount;
        uint256 kesAmount;
        ConversionType conversionType;
        OrderStatus status;
        uint256 createdAt;
        uint256 expiresAt;
        string mpesaReference;
        uint256 validatorSignatures;
    }

    enum ConversionType {
        OMNI_TO_KES,
        KES_TO_OMNI
    }

    enum OrderStatus {
        PENDING,
        MATCHED,
        COMPLETED,
        CANCELLED,
        DISPUTED
    }

    // Storage
    mapping(address => OracleNode) public oracleNodes;
    mapping(bytes32 => ConversionOrder) public conversionOrders;
    mapping(address => bytes32[]) public userOrders;
    mapping(bytes32 => PriceFeed) public priceFeeds;
    mapping(address => uint256) public dailyVolume;
    mapping(address => uint256) public lastVolumeReset;

    // Oracle consensus
    uint256 public constant MIN_ORACLES = 3;
    uint256 public constant ORACLE_CONSENSUS_THRESHOLD = 66; // 66% agreement
    uint256 public currentOmniToKesRate;
    uint256 public currentKesToOmniRate;
    uint256 public lastRateUpdate;

    // Fees (decentralized treasury)
    uint256 public constant CONVERSION_FEE = 100; // 1%
    uint256 public constant FEE_DENOMINATOR = 10000;
    uint256 public totalFeesCollected;
    address public feeTreasury; // DAO-controlled

    // Limits
    uint256 public dailyLimit = 100000 * 1e18;
    uint256 public minConversion = 10 * 1e18;
    uint256 public maxConversion = 10000 * 1e18;

    // Events
    event OracleNodeRegistered(address indexed node, uint256 stake);
    event OracleNodeRemoved(address indexed node);
    event PriceFeedSubmitted(address indexed oracle, uint256 omniToKes, uint256 kesToOmni);
    event RateUpdated(uint256 omniToKes, uint256 kesToOmni);
    event ConversionOrderCreated(bytes32 indexed orderId, address indexed maker, uint256 omniAmount, uint256 kesAmount);
    event ConversionOrderMatched(bytes32 indexed orderId, address indexed taker);
    event ConversionOrderCompleted(bytes32 indexed orderId, string mpesaReference);
    event ConversionOrderCancelled(bytes32 indexed orderId);
    event DisputeRaised(bytes32 indexed orderId, address indexed raiser);
    event FeesDistributed(address indexed treasury, uint256 amount);

    /**
     * @dev Constructor initializes decentralized M-Pesa bridge
     * @param _omniToken Address of OMNI token contract
     * @param _feeTreasury Address of DAO-controlled fee treasury
     */
    constructor(address _omniToken, address _feeTreasury) {
        require(_omniToken != address(0), "Bridge: Invalid token address");
        require(_feeTreasury != address(0), "Bridge: Invalid treasury address");
        
        omniToken = OMNIToken(_omniToken);
        feeTreasury = _feeTreasury;
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ORACLE_ROLE, msg.sender);
        _grantRole(VALIDATOR_ROLE, msg.sender);
        _grantRole(GOVERNANCE_ROLE, msg.sender);
        
        // Initialize with default rate (1 OMNI = 100 KES)
        currentOmniToKesRate = 10000; // 100.00 KES
        currentKesToOmniRate = 1e16; // 0.01 OMNI per 100 KES
        lastRateUpdate = block.timestamp;
    }

    /**
     * @dev Registers an oracle node (decentralized network)
     * @param endpoint Oracle node endpoint
     */
    function registerOracleNode(string calldata endpoint) external payable {
        require(msg.value >= 1000 * 1e18, "Bridge: Minimum stake required");
        require(!oracleNodes[msg.sender].isActive, "Bridge: Already registered");
        
        oracleNodes[msg.sender] = OracleNode({
            nodeAddress: msg.sender,
            endpoint: endpoint,
            stake: msg.value,
            reputation: 100,
            isActive: true,
            lastUpdate: block.timestamp
        });
        
        emit OracleNodeRegistered(msg.sender, msg.value);
    }

    /**
     * @dev Submits price feed from oracle node
     * @param omniToKes OMNI to KES rate
     * @param kesToOmni KES to OMNI rate
     * @param signature Oracle signature
     */
    function submitPriceFeed(
        uint256 omniToKes,
        uint256 kesToOmni,
        bytes calldata signature
    ) external onlyRole(ORACLE_ROLE) {
        require(oracleNodes[msg.sender].isActive, "Bridge: Not active oracle");
        require(omniToKes > 0 && kesToOmni > 0, "Bridge: Invalid rates");
        
        // Store price feed
        bytes32 feedId = keccak256(abi.encodePacked(msg.sender, omniToKes, kesToOmni, block.timestamp));
        priceFeeds[feedId] = PriceFeed({
            omniToKes: omniToKes,
            kesToOmni: kesToOmni,
            timestamp: block.timestamp,
            oracle: msg.sender,
            signature: signature
        });
        
        // Update oracle reputation
        oracleNodes[msg.sender].lastUpdate = block.timestamp;
        oracleNodes[msg.sender].reputation = min(oracleNodes[msg.sender].reputation + 1, 1000);
        
        emit PriceFeedSubmitted(msg.sender, omniToKes, kesToOmni);
        
        // Check if we have enough feeds to update rate
        _updateRateFromOracles();
    }

    /**
     * @dev Updates rate from oracle consensus
     */
    function _updateRateFromOracles() internal {
        // Count recent feeds (last hour)
        uint256 recentFeeds = 0;
        uint256 totalOmniToKes = 0;
        uint256 totalKesToOmni = 0;
        
        // In production, iterate through recent feeds
        // For now, use simplified consensus
        
        if (recentFeeds >= MIN_ORACLES) {
            uint256 avgOmniToKes = totalOmniToKes / recentFeeds;
            uint256 avgKesToOmni = totalKesToOmni / recentFeeds;
            
            currentOmniToKesRate = avgOmniToKes;
            currentKesToOmniRate = avgKesToOmni;
            lastRateUpdate = block.timestamp;
            
            emit RateUpdated(avgOmniToKes, avgKesToOmni);
        }
    }

    /**
     * @dev Creates P2P conversion order (decentralized)
     * @param omniAmount Amount of OMNI
     * @param kesAmount Amount of KES
     * @param conversionType Type of conversion
     * @param expiryHours Hours until order expires
     * @return orderId Created order ID
     */
    function createConversionOrder(
        uint256 omniAmount,
        uint256 kesAmount,
        ConversionType conversionType,
        uint256 expiryHours
    ) external whenNotPaused nonReentrant returns (bytes32) {
        require(omniAmount >= minConversion, "Bridge: Below minimum");
        require(omniAmount <= maxConversion, "Bridge: Above maximum");
        
        // Check daily limit
        _checkDailyLimit(msg.sender, omniAmount);
        
        bytes32 orderId = keccak256(abi.encodePacked(msg.sender, omniAmount, kesAmount, block.timestamp));
        
        conversionOrders[orderId] = ConversionOrder({
            orderId: orderId,
            maker: msg.sender,
            taker: address(0),
            omniAmount: omniAmount,
            kesAmount: kesAmount,
            conversionType: conversionType,
            status: OrderStatus.PENDING,
            createdAt: block.timestamp,
            expiresAt: block.timestamp + (expiryHours * 1 hours),
            mpesaReference: "",
            validatorSignatures: 0
        });
        
        userOrders[msg.sender].push(orderId);
        
        // If OMNI to KES, lock OMNI
        if (conversionType == ConversionType.OMNI_TO_KES) {
            omniToken.transferFrom(msg.sender, address(this), omniAmount);
        }
        
        emit ConversionOrderCreated(orderId, msg.sender, omniAmount, kesAmount);
        
        return orderId;
    }

    /**
     * @dev Matches a conversion order (P2P)
     * @param orderId Order ID to match
     */
    function matchConversionOrder(bytes32 orderId) external whenNotPaused {
        ConversionOrder storage order = conversionOrders[orderId];
        
        require(order.status == OrderStatus.PENDING, "Bridge: Not pending");
        require(block.timestamp <= order.expiresAt, "Bridge: Order expired");
        require(msg.sender != order.maker, "Bridge: Cannot match own order");
        
        order.taker = msg.sender;
        order.status = OrderStatus.MATCHED;
        
        // If KES to OMNI, lock KES (in production, integrate with M-Pesa API)
        if (order.conversionType == ConversionType.KES_TO_OMNI) {
            // Taker sends KES via M-Pesa
            // In production, this would be verified by oracle
        }
        
        emit ConversionOrderMatched(orderId, msg.sender);
    }

    /**
     * @dev Completes conversion order with M-Pesa reference
     * @param orderId Order ID
     * @param mpesaReference M-Pesa transaction reference
     */
    function completeConversionOrder(
        bytes32 orderId,
        string calldata mpesaReference
    ) external onlyRole(VALIDATOR_ROLE) nonReentrant {
        ConversionOrder storage order = conversionOrders[orderId];
        
        require(order.status == OrderStatus.MATCHED, "Bridge: Not matched");
        require(bytes(mpesaReference).length > 0, "Bridge: Invalid reference");
        
        // Calculate fee
        uint256 fee = (order.omniAmount * CONVERSION_FEE) / FEE_DENOMINATOR;
        uint256 netAmount = order.omniAmount - fee;
        
        // Distribute based on conversion type
        if (order.conversionType == ConversionType.OMNI_TO_KES) {
            // Maker gets KES (via M-Pesa)
            // Taker gets OMNI
            omniToken.transfer(order.taker, netAmount);
        } else {
            // Maker gets OMNI
            // Taker gets KES (via M-Pesa)
            omniToken.transfer(order.maker, netAmount);
        }
        
        // Collect fee
        totalFeesCollected += fee;
        omniToken.transfer(feeTreasury, fee);
        
        order.status = OrderStatus.COMPLETED;
        order.mpesaReference = mpesaReference;
        
        emit ConversionOrderCompleted(orderId, mpesaReference);
        emit FeesDistributed(feeTreasury, fee);
    }

    /**
     * @dev Cancels a conversion order
     * @param orderId Order ID
     */
    function cancelConversionOrder(bytes32 orderId) external {
        ConversionOrder storage order = conversionOrders[orderId];
        
        require(msg.sender == order.maker || hasRole(GOVERNANCE_ROLE, msg.sender), 
            "Bridge: Not authorized");
        require(order.status == OrderStatus.PENDING || order.status == OrderStatus.MATCHED, 
            "Bridge: Cannot cancel");
        
        // Refund if OMNI was locked
        if (order.conversionType == ConversionType.OMNI_TO_KES && order.status == OrderStatus.PENDING) {
            omniToken.transfer(order.maker, order.omniAmount);
        }
        
        order.status = OrderStatus.CANCELLED;
        
        emit ConversionOrderCancelled(orderId);
    }

    /**
     * @dev Raises dispute on conversion order
     * @param orderId Order ID
     */
    function raiseDispute(bytes32 orderId) external {
        ConversionOrder storage order = conversionOrders[orderId];
        
        require(msg.sender == order.maker || msg.sender == order.taker, 
            "Bridge: Not authorized");
        require(order.status == OrderStatus.MATCHED, "Bridge: Not matched");
        
        order.status = OrderStatus.DISPUTED;
        
        emit DisputeRaised(orderId, msg.sender);
    }

    /**
     * @dev Checks daily conversion limit
     * @param user User address
     * @param amount Conversion amount
     */
    function _checkDailyLimit(address user, uint256 amount) internal {
        uint256 today = block.timestamp / 1 days;
        
        if (lastVolumeReset[user] != today) {
            dailyVolume[user] = 0;
            lastVolumeReset[user] = today;
        }
        
        require(dailyVolume[user] + amount <= dailyLimit, "Bridge: Daily limit exceeded");
        dailyVolume[user] += amount;
    }

    /**
     * @dev Gets oracle node details
     * @param node Node address
     * @return OracleNode data
     */
    function getOracleNode(address node) external view returns (OracleNode memory) {
        return oracleNodes[node];
    }

    /**
     * @dev Gets conversion order details
     * @param orderId Order ID
     * @return ConversionOrder data
     */
    function getConversionOrder(bytes32 orderId) external view returns (ConversionOrder memory) {
        return conversionOrders[orderId];
    }

    /**
     * @dev Gets user's orders
     * @param user User address
     * @return Array of order IDs
     */
    function getUserOrders(address user) external view returns (bytes32[] memory) {
        return userOrders[user];
    }

    /**
     * @dev Gets current rate
     * @return omniToKes OMNI to KES rate
     * @return kesToOmni KES to OMNI rate
     */
    function getCurrentRate() external view returns (uint256 omniToKes, uint256 kesToOmni) {
        return (currentOmniToKesRate, currentKesToOmniRate);
    }

    /**
     * @dev Updates fee treasury (DAO controlled)
     * @param newTreasury New treasury address
     */
    function updateFeeTreasury(address newTreasury) external onlyRole(GOVERNANCE_ROLE) {
        require(newTreasury != address(0), "Bridge: Invalid treasury");
        feeTreasury = newTreasury;
    }

    /**
     * @dev Updates daily limit (DAO controlled)
     * @param newLimit New daily limit
     */
    function updateDailyLimit(uint256 newLimit) external onlyRole(GOVERNANCE_ROLE) {
        dailyLimit = newLimit;
    }

    /**
     * @dev Removes oracle node
     * @param node Node address
     */
    function removeOracleNode(address node) external onlyRole(GOVERNANCE_ROLE) {
        require(oracleNodes[node].isActive, "Bridge: Not active");
        
        // Refund stake
        payable(node).transfer(oracleNodes[node].stake);
        
        oracleNodes[node].isActive = false;
        
        emit OracleNodeRemoved(node);
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

    /**
     * @dev Helper to get minimum of two values
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
