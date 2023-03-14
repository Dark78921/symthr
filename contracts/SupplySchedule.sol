pragma solidity ^0.5.16;

// Inheritance
import "./Owned.sol";
import "./interfaces/ISupplySchedule.sol";

// Libraries
import "./SafeDecimalMath.sol";
import "./Math.sol";

// Internal references
import "./Proxy.sol";
import "./interfaces/ISynthetix.sol";
import "./interfaces/IERC20.sol";

// https://docs.synthetix.io/contracts/source/contracts/supplyschedule
contract SupplySchedule is Owned, ISupplySchedule {
    using SafeMath for uint256;
    using SafeDecimalMath for uint256;
    using Math for uint256;

    bytes32 public constant CONTRACT_NAME = "SupplySchedule";

    // Time of the last inflation supply mint event
    uint256 public lastMintEvent;

    // Counter for number of weeks since the start of supply inflation
    uint256 public weekCounter;

    uint256 public constant INFLATION_START_DATE = 1551830400; // 2019-03-06T00:00:00+00:00

    // The number of SNX rewarded to the caller of Synthetix.mint()
    uint256 public minterReward = 100 * 1e18;

    // The number of SNX minted per week
    uint256 public inflationAmount;

    uint256 public maxInflationAmount = 3e6 * 1e18; // max inflation amount 3,000,000

    // Address of the SynthetixProxy for the onlySynthetix modifier
    address payable public synthetixProxy;

    // Max SNX rewards for minter
    uint256 public constant MAX_MINTER_REWARD = 200 * 1e18;

    // How long each inflation period is before mint can be called
    uint256 public constant MINT_PERIOD_DURATION = 1 weeks;

    uint256 public constant MINT_BUFFER = 1 days;

    constructor(
        address _owner,
        uint256 _lastMintEvent,
        uint256 _currentWeek
    ) public Owned(_owner) {
        lastMintEvent = _lastMintEvent;
        weekCounter = _currentWeek;
    }

    // ========== VIEWS ==========

    /**
     * @return The amount of SNX mintable for the inflationary supply
     */
    function mintableSupply() external view returns (uint256) {
        uint256 totalAmount;

        if (!isMintable()) {
            return totalAmount;
        }

        // Get total amount to mint * by number of weeks to mint
        totalAmount = inflationAmount.mul(weeksSinceLastIssuance());

        return totalAmount;
    }

    /**
     * @dev Take timeDiff in seconds (Dividend) and MINT_PERIOD_DURATION as (Divisor)
     * @return Calculate the numberOfWeeks since last mint rounded down to 1 week
     */
    function weeksSinceLastIssuance() public view returns (uint256) {
        // Get weeks since lastMintEvent
        // If lastMintEvent not set or 0, then start from inflation start date.
        uint256 timeDiff = lastMintEvent > 0 ? now.sub(lastMintEvent) : now.sub(INFLATION_START_DATE);
        return timeDiff.div(MINT_PERIOD_DURATION);
    }

    /**
     * @return boolean whether the MINT_PERIOD_DURATION (7 days)
     * has passed since the lastMintEvent.
     * */
    function isMintable() public view returns (bool) {
        if (now - lastMintEvent > MINT_PERIOD_DURATION) {
            return true;
        }
        return false;
    }

    // ========== MUTATIVE FUNCTIONS ==========

    /**
     * @notice Record the mint event from Synthetix by incrementing the inflation
     * week counter for the number of weeks minted (probabaly always 1)
     * and store the time of the event.
     * @param supplyMinted the amount of SNX the total supply was inflated by.
     * @return minterReward the amount of SNX reward for caller
     * */
    function recordMintEvent(uint256 supplyMinted) external onlySynthetix returns (uint256) {
        uint256 numberOfWeeksIssued = weeksSinceLastIssuance();

        // add number of weeks minted to weekCounter
        weekCounter = weekCounter.add(numberOfWeeksIssued);

        // Update mint event to latest week issued (start date + number of weeks issued * seconds in week)
        // 1 day time buffer is added so inflation is minted after feePeriod closes
        lastMintEvent = INFLATION_START_DATE.add(weekCounter.mul(MINT_PERIOD_DURATION)).add(MINT_BUFFER);

        emit SupplyMinted(supplyMinted, numberOfWeeksIssued, lastMintEvent, now);
        return minterReward;
    }

    // ========== SETTERS ========== */

    /**
     * @notice Sets the reward amount of SNX for the caller of the public
     * function Synthetix.mint().
     * This incentivises anyone to mint the inflationary supply and the mintr
     * Reward will be deducted from the inflationary supply and sent to the caller.
     * @param amount the amount of SNX to reward the minter.
     * */
    function setMinterReward(uint256 amount) external onlyOwner {
        require(amount <= MAX_MINTER_REWARD, "Reward cannot exceed max minter reward");
        minterReward = amount;
        emit MinterRewardUpdated(minterReward);
    }

    /**
     * @notice Set the SynthetixProxy should it ever change.
     * SupplySchedule requires Synthetix address as it has the authority
     * to record mint event.
     * */
    function setSynthetixProxy(ISynthetix _synthetixProxy) external onlyOwner {
        require(address(_synthetixProxy) != address(0), "Address cannot be 0");
        synthetixProxy = address(uint160(address(_synthetixProxy)));
        emit SynthetixProxyUpdated(synthetixProxy);
    }

    /**
     * @notice Set the weekly inflationAmount.
     * Protocol DAO sets the amount based on the target staking ratio
     * Will be replaced with on-chain calculation of the staking ratio
     * */
    function setInflationAmount(uint256 amount) external onlyOwner {
        require(amount <= maxInflationAmount, "Amount above maximum inflation");
        inflationAmount = amount;
        emit InflationAmountUpdated(inflationAmount);
    }

    function setMaxInflationAmount(uint256 amount) external onlyOwner {
        maxInflationAmount = amount;
        emit MaxInflationAmountUpdated(inflationAmount);
    }

    // ========== MODIFIERS ==========

    /**
     * @notice Only the Synthetix contract is authorised to call this function
     * */
    modifier onlySynthetix() {
        require(
            msg.sender == address(Proxy(address(synthetixProxy)).target()),
            "Only the synthetix contract can perform this action"
        );
        _;
    }

    /* ========== EVENTS ========== */
    /**
     * @notice Emitted when the inflationary supply is minted
     * */
    event SupplyMinted(uint256 supplyMinted, uint256 numberOfWeeksIssued, uint256 lastMintEvent, uint256 timestamp);

    /**
     * @notice Emitted when the SNX minter reward amount is updated
     * */
    event MinterRewardUpdated(uint256 newRewardAmount);

    /**
     * @notice Emitted when the Inflation amount is updated
     * */
    event InflationAmountUpdated(uint256 newInflationAmount);

    /**
     * @notice Emitted when the max Inflation amount is updated
     * */
    event MaxInflationAmountUpdated(uint256 newInflationAmount);

    /**
     * @notice Emitted when setSynthetixProxy is called changing the Synthetix Proxy address
     * */
    event SynthetixProxyUpdated(address newAddress);
}
