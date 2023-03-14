pragma solidity ^0.5.16;

// Internal dependencies.
import "./Pausable.sol";
import "./MixinResolver.sol";
import "./Owned.sol";

// External dependencies.
// import "openzeppelin-solidity-2.3.0/contracts/token/ERC20/SafeERC20.sol";
// import "openzeppelin-solidity-2.3.0/contracts/utils/ReentrancyGuard.sol";
import "./externals/openzeppelin/SafeERC20.sol";
import "./externals/openzeppelin/ReentrancyGuard.sol";

// Libraries.
import "./SafeDecimalMath.sol";

// Internal references.
import "./interfaces/ITradingRewards.sol";
import "./interfaces/IExchanger.sol";

// https://docs.synthetix.io/contracts/source/contracts/tradingrewards
contract TradingRewards is ITradingRewards, ReentrancyGuard, Owned, Pausable, MixinResolver {
    using SafeMath for uint256;
    using SafeDecimalMath for uint256;
    using SafeERC20 for IERC20;

    /* ========== STATE VARIABLES ========== */

    uint256 private _currentPeriodID;
    uint256 private _balanceAssignedToRewards;
    mapping(uint256 => Period) private _periods;

    struct Period {
        bool isFinalized;
        uint256 recordedFees;
        uint256 totalRewards;
        uint256 availableRewards;
        mapping(address => uint256) unaccountedFeesForAccount;
    }

    address private _periodController;

    /* ========== ADDRESS RESOLVER CONFIGURATION ========== */

    bytes32 private constant CONTRACT_EXCHANGER = "Exchanger";
    bytes32 private constant CONTRACT_SYNTHETIX = "Synthetix";

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address owner,
        address periodController,
        address resolver
    ) public Owned(owner) MixinResolver(resolver) {
        require(periodController != address(0), "Invalid period controller");

        _periodController = periodController;
    }

    /* ========== VIEWS ========== */

    function resolverAddressesRequired() public view returns (bytes32[] memory addresses) {
        addresses = new bytes32[](2);
        addresses[0] = CONTRACT_EXCHANGER;
        addresses[1] = CONTRACT_SYNTHETIX;
    }

    function synthetix() internal view returns (IERC20) {
        return IERC20(requireAndGetAddress(CONTRACT_SYNTHETIX));
    }

    function exchanger() internal view returns (IExchanger) {
        return IExchanger(requireAndGetAddress(CONTRACT_EXCHANGER));
    }

    function getAvailableRewards() external view returns (uint256) {
        return _balanceAssignedToRewards;
    }

    function getUnassignedRewards() external view returns (uint256) {
        return synthetix().balanceOf(address(this)).sub(_balanceAssignedToRewards);
    }

    function getRewardsToken() external view returns (address) {
        return address(synthetix());
    }

    function getPeriodController() external view returns (address) {
        return _periodController;
    }

    function getCurrentPeriod() external view returns (uint256) {
        return _currentPeriodID;
    }

    function getPeriodIsClaimable(uint256 periodID) external view returns (bool) {
        return _periods[periodID].isFinalized;
    }

    function getPeriodIsFinalized(uint256 periodID) external view returns (bool) {
        return _periods[periodID].isFinalized;
    }

    function getPeriodRecordedFees(uint256 periodID) external view returns (uint256) {
        return _periods[periodID].recordedFees;
    }

    function getPeriodTotalRewards(uint256 periodID) external view returns (uint256) {
        return _periods[periodID].totalRewards;
    }

    function getPeriodAvailableRewards(uint256 periodID) external view returns (uint256) {
        return _periods[periodID].availableRewards;
    }

    function getUnaccountedFeesForAccountForPeriod(address account, uint256 periodID) external view returns (uint256) {
        return _periods[periodID].unaccountedFeesForAccount[account];
    }

    function getAvailableRewardsForAccountForPeriod(address account, uint256 periodID) external view returns (uint256) {
        return _calculateRewards(account, periodID);
    }

    function getAvailableRewardsForAccountForPeriods(address account, uint256[] calldata periodIDs)
        external
        view
        returns (uint256 totalRewards)
    {
        for (uint256 i = 0; i < periodIDs.length; i++) {
            uint256 periodID = periodIDs[i];

            totalRewards = totalRewards.add(_calculateRewards(account, periodID));
        }
    }

    function _calculateRewards(address account, uint256 periodID) internal view returns (uint256) {
        Period storage period = _periods[periodID];
        if (period.availableRewards == 0 || period.recordedFees == 0 || !period.isFinalized) {
            return 0;
        }

        uint256 accountFees = period.unaccountedFeesForAccount[account];
        if (accountFees == 0) {
            return 0;
        }

        uint256 participationRatio = accountFees.divideDecimal(period.recordedFees);
        return participationRatio.multiplyDecimal(period.totalRewards);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function claimRewardsForPeriod(uint256 periodID) external nonReentrant notPaused {
        _claimRewards(msg.sender, periodID);
    }

    function claimRewardsForPeriods(uint256[] calldata periodIDs) external nonReentrant notPaused {
        for (uint256 i = 0; i < periodIDs.length; i++) {
            uint256 periodID = periodIDs[i];

            // Will revert if any independent claim reverts.
            _claimRewards(msg.sender, periodID);
        }
    }

    function _claimRewards(address account, uint256 periodID) internal {
        Period storage period = _periods[periodID];
        require(period.isFinalized, "Period is not finalized");

        uint256 amountToClaim = _calculateRewards(account, periodID);
        require(amountToClaim > 0, "No rewards available");

        period.unaccountedFeesForAccount[account] = 0;
        period.availableRewards = period.availableRewards.sub(amountToClaim);

        _balanceAssignedToRewards = _balanceAssignedToRewards.sub(amountToClaim);

        synthetix().safeTransfer(account, amountToClaim);

        emit RewardsClaimed(account, amountToClaim, periodID);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function recordExchangeFeeForAccount(uint256 usdFeeAmount, address account) external onlyExchanger {
        Period storage period = _periods[_currentPeriodID];
        // Note: In theory, the current period will never be finalized.
        // Such a require could be added here, but it would just spend gas, since it should always satisfied.

        period.unaccountedFeesForAccount[account] = period.unaccountedFeesForAccount[account].add(usdFeeAmount);
        period.recordedFees = period.recordedFees.add(usdFeeAmount);

        emit ExchangeFeeRecorded(account, usdFeeAmount, _currentPeriodID);
    }

    function closeCurrentPeriodWithRewards(uint256 rewards) external onlyPeriodController {
        uint256 currentBalance = synthetix().balanceOf(address(this));
        uint256 availableForNewRewards = currentBalance.sub(_balanceAssignedToRewards);
        require(rewards <= availableForNewRewards, "Insufficient free rewards");

        Period storage period = _periods[_currentPeriodID];

        period.totalRewards = rewards;
        period.availableRewards = rewards;
        period.isFinalized = true;

        _balanceAssignedToRewards = _balanceAssignedToRewards.add(rewards);

        emit PeriodFinalizedWithRewards(_currentPeriodID, rewards);

        _currentPeriodID = _currentPeriodID.add(1);

        emit NewPeriodStarted(_currentPeriodID);
    }

    function recoverTokens(address tokenAddress, address recoverAddress) external onlyOwner {
        _validateRecoverAddress(recoverAddress);
        require(tokenAddress != address(synthetix()), "Must use another function");

        IERC20 token = IERC20(tokenAddress);

        uint256 tokenBalance = token.balanceOf(address(this));
        require(tokenBalance > 0, "No tokens to recover");

        token.safeTransfer(recoverAddress, tokenBalance);

        emit TokensRecovered(tokenAddress, recoverAddress, tokenBalance);
    }

    function recoverUnassignedRewardTokens(address recoverAddress) external onlyOwner {
        _validateRecoverAddress(recoverAddress);

        uint256 tokenBalance = synthetix().balanceOf(address(this));
        require(tokenBalance > 0, "No tokens to recover");

        uint256 unassignedBalance = tokenBalance.sub(_balanceAssignedToRewards);
        require(unassignedBalance > 0, "No tokens to recover");

        synthetix().safeTransfer(recoverAddress, unassignedBalance);

        emit UnassignedRewardTokensRecovered(recoverAddress, unassignedBalance);
    }

    function recoverAssignedRewardTokensAndDestroyPeriod(address recoverAddress, uint256 periodID) external onlyOwner {
        _validateRecoverAddress(recoverAddress);
        require(periodID < _currentPeriodID, "Cannot recover from active");

        Period storage period = _periods[periodID];
        require(period.availableRewards > 0, "No rewards available to recover");

        uint256 amount = period.availableRewards;
        synthetix().safeTransfer(recoverAddress, amount);

        _balanceAssignedToRewards = _balanceAssignedToRewards.sub(amount);

        delete _periods[periodID];

        emit AssignedRewardTokensRecovered(recoverAddress, amount, periodID);
    }

    function _validateRecoverAddress(address recoverAddress) internal view {
        if (recoverAddress == address(0) || recoverAddress == address(this)) {
            revert("Invalid recover address");
        }
    }

    function setPeriodController(address newPeriodController) external onlyOwner {
        require(newPeriodController != address(0), "Invalid period controller");

        _periodController = newPeriodController;

        emit PeriodControllerChanged(newPeriodController);
    }

    /* ========== MODIFIERS ========== */

    modifier onlyPeriodController() {
        require(msg.sender == _periodController, "Caller not period controller");
        _;
    }

    modifier onlyExchanger() {
        require(msg.sender == address(exchanger()), "Only Exchanger can invoke this");
        _;
    }

    /* ========== EVENTS ========== */

    event ExchangeFeeRecorded(address indexed account, uint256 amount, uint256 periodID);
    event RewardsClaimed(address indexed account, uint256 amount, uint256 periodID);
    event NewPeriodStarted(uint256 periodID);
    event PeriodFinalizedWithRewards(uint256 periodID, uint256 rewards);
    event TokensRecovered(address tokenAddress, address recoverAddress, uint256 amount);
    event UnassignedRewardTokensRecovered(address recoverAddress, uint256 amount);
    event AssignedRewardTokensRecovered(address recoverAddress, uint256 amount, uint256 periodID);
    event PeriodControllerChanged(address newPeriodController);
}
