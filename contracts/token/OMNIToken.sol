// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title OMNIToken
 * @dev The native token of The Omniversity Protocol
 * @notice $OMNI is used for:
 * - Learning rewards (mining)
 * - Tuition payments
 * - DAO governance
 * - Guild investments
 * - M-Pesa conversions
 */
contract OMNIToken is ERC20, ERC20Burnable, ERC20Pausable, AccessControl, ReentrancyGuard {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");

    // Tokenomics
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 1e18; // 1 billion tokens
    uint256 public constant LEARNING_REWARD_POOL = 400_000_000 * 1e18; // 40% for learning rewards
    uint256 public constant TEAM_ALLOCATION = 150_000_000 * 1e18; // 15% for team
    uint256 public constant DAO_TREASURY = 200_000_000 * 1e18; // 20% for DAO
    uint256 public constant ECOSYSTEM_FUND = 150_000_000 * 1e18; // 15% for ecosystem
    uint256 public constant PUBLIC_SALE = 100_000_000 * 1e18; // 10% for public sale

    // Vesting schedules
    uint256 public constant TEAM_VESTING_DURATION = 365 days;
    uint256 public constant TEAM_CLIFF_DURATION = 180 days;

    // M-Pesa conversion fee (1%)
    uint256 public constant MPESA_CONVERSION_FEE = 100; // 1% in basis points
    uint256 public constant FEE_DENOMINATOR = 10000;

    // State variables
    uint256 public totalMinted;
    uint256 public totalBurned;
    mapping(address => uint256) public vestingStart;
    mapping(address => uint256) public vestingAmount;
    mapping(address => uint256) public claimedAmount;

    // Events
    event TokensMinted(address indexed to, uint256 amount, string reason);
    event TokensBurned(address indexed from, uint256 amount);
    event VestingScheduleCreated(address indexed beneficiary, uint256 amount, uint256 start);
    event TokensClaimed(address indexed beneficiary, uint256 amount);
    event ConversionFeeCollected(address indexed from, uint256 feeAmount);
    event GovernanceProposalExecuted(address indexed proposalId, bool success);

    /**
     * @dev Constructor sets up the token with initial supply and roles
     * @param _initialRecipient Address to receive initial token allocation
     */
    constructor(address _initialRecipient) ERC20("Omniversity Token", "OMNI") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        _grantRole(GOVERNANCE_ROLE, msg.sender);

        // Mint initial allocation to DAO treasury
        _mint(_initialRecipient, DAO_TREASURY);
        totalMinted = DAO_TREASURY;

        emit TokensMinted(_initialRecipient, DAO_TREASURY, "Initial DAO Treasury Allocation");
    }

    /**
     * @dev Mints new tokens (only MINTER_ROLE)
     * @param to Address to receive tokens
     * @param amount Amount to mint
     * @param reason Reason for minting (e.g., "Learning Reward", "Guild Profit")
     */
    function mint(address to, uint256 amount, string calldata reason) 
        external 
        onlyRole(MINTER_ROLE) 
        nonReentrant 
    {
        require(totalMinted + amount <= MAX_SUPPLY, "OMNI: Max supply exceeded");
        require(to != address(0), "OMNI: Mint to zero address");
        
        _mint(to, amount);
        totalMinted += amount;
        
        emit TokensMinted(to, amount, reason);
    }

    /**
     * @dev Burns tokens from circulation
     * @param amount Amount to burn
     */
    function burn(uint256 amount) public override {
        require(balanceOf(msg.sender) >= amount, "OMNI: Insufficient balance");
        super.burn(amount);
        totalBurned += amount;
        emit TokensBurned(msg.sender, amount);
    }

    /**
     * @dev Creates a vesting schedule for team/advisor tokens
     * @param beneficiary Address receiving vested tokens
     * @param amount Total amount to vest
     */
    function createVesting(address beneficiary, uint256 amount) 
        external 
        onlyRole(GOVERNANCE_ROLE) 
    {
        require(beneficiary != address(0), "OMNI: Vesting to zero address");
        require(vestingAmount[beneficiary] == 0, "OMNI: Vesting already exists");
        
        vestingStart[beneficiary] = block.timestamp;
        vestingAmount[beneficiary] = amount;
        
        emit VestingScheduleCreated(beneficiary, amount, block.timestamp);
    }

    /**
     * @dev Claims vested tokens
     */
    function claimVested() external nonReentrant {
        require(vestingAmount[msg.sender] > 0, "OMNI: No vesting schedule");
        require(block.timestamp >= vestingStart[msg.sender] + TEAM_CLIFF_DURATION, 
            "OMNI: Cliff period not reached");
        
        uint256 vestedAmount = _calculateVestedAmount(msg.sender);
        uint256 claimable = vestedAmount - claimedAmount[msg.sender];
        
        require(claimable > 0, "OMNI: Nothing to claim");
        
        claimedAmount[msg.sender] += claimable;
        _mint(msg.sender, claimable);
        totalMinted += claimable;
        
        emit TokensMinted(msg.sender, claimable, "Vesting Claim");
        emit TokensClaimed(msg.sender, claimable);
    }

    /**
     * @dev Calculates vested amount for a beneficiary
     * @param beneficiary Address to check
     * @return Vested amount
     */
    function _calculateVestedAmount(address beneficiary) internal view returns (uint256) {
        if (block.timestamp < vestingStart[beneficiary] + TEAM_CLIFF_DURATION) {
            return 0;
        }
        
        uint256 elapsed = block.timestamp - vestingStart[beneficiary];
        if (elapsed >= TEAM_VESTING_DURATION) {
            return vestingAmount[beneficiary];
        }
        
        return (vestingAmount[beneficiary] * elapsed) / TEAM_VESTING_DURATION;
    }

    /**
     * @dev Gets claimable amount for a beneficiary
     * @param beneficiary Address to check
     * @return Claimable amount
     */
    function getClaimableAmount(address beneficiary) external view returns (uint256) {
        uint256 vestedAmount = _calculateVestedAmount(beneficiary);
        return vestedAmount - claimedAmount[beneficiary];
    }

    /**
     * @dev Converts OMNI to KES with 1% fee
     * @param amount Amount of OMNI to convert
     * @return netAmount Amount after fee deduction
     * @return feeAmount Fee collected
     */
    function convertToKES(uint256 amount) external nonReentrant returns (uint256 netAmount, uint256 feeAmount) {
        require(balanceOf(msg.sender) >= amount, "OMNI: Insufficient balance");
        
        feeAmount = (amount * MPESA_CONVERSION_FEE) / FEE_DENOMINATOR;
        netAmount = amount - feeAmount;
        
        // Burn the fee (deflationary mechanism)
        _burn(msg.sender, feeAmount);
        totalBurned += feeAmount;
        
        // Transfer net amount to M-Pesa bridge
        _burn(msg.sender, netAmount);
        
        emit ConversionFeeCollected(msg.sender, feeAmount);
        emit TokensBurned(msg.sender, amount);
        
        return (netAmount, feeAmount);
    }

    /**
     * @dev Pauses token transfers
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @dev Unpauses token transfers
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @dev Override required by Solidity
     */
    function _beforeTokenTransfer(address from, address to, uint256 amount)
        internal
        whenNotPaused
        override(ERC20, ERC20Pausable)
    {
        super._beforeTokenTransfer(from, to, amount);
    }

    /**
     * @dev Returns remaining mintable supply
     * @return Remaining supply
     */
    function remainingMintableSupply() external view returns (uint256) {
        return MAX_SUPPLY - totalMinted;
    }

    /**
     * @dev Returns circulating supply (minted - burned)
     * @return Circulating supply
     */
    function circulatingSupply() external view returns (uint256) {
        return totalMinted - totalBurned;
    }
}
