pragma solidity ^0.5.16;

// Inheritance
import "./Owned.sol";
import "./PerpsV2SettingsMixin.sol";

// Internal references
import "./interfaces/IPerpsV2Settings.sol";
import "./interfaces/IPerpsV2Market.sol";

// market manager is still the V1 one
import "./interfaces/IFuturesMarketManager.sol";

contract PerpsV2Settings is Owned, PerpsV2SettingsMixin, IPerpsV2Settings {
    /* ========== CONSTANTS ========== */

    /* ---------- Address Resolver Configuration ---------- */

    bytes32 internal constant CONTRACT_FUTURES_MARKET_MANAGER = "FuturesMarketManager";

    bytes32 public constant CONTRACT_NAME = "PerpsV2Settings";

    /* ========== CONSTRUCTOR ========== */

    constructor(address _owner, address _resolver) public Owned(_owner) PerpsV2SettingsMixin(_resolver) {}

    /* ========== VIEWS ========== */

    function resolverAddressesRequired() public view returns (bytes32[] memory addresses) {
        bytes32[] memory existingAddresses = PerpsV2SettingsMixin.resolverAddressesRequired();
        bytes32[] memory newAddresses = new bytes32[](1);
        newAddresses[0] = CONTRACT_FUTURES_MARKET_MANAGER;
        addresses = combineArrays(existingAddresses, newAddresses);
    }

    function _futuresMarketManager() internal view returns (IFuturesMarketManager) {
        return IFuturesMarketManager(requireAndGetAddress(CONTRACT_FUTURES_MARKET_MANAGER));
    }

    /* ---------- Getters ---------- */

    /*
     * The fee charged when opening a position on the heavy side of a market.
     */
    function baseFee(bytes32 _marketKey) external view returns (uint256) {
        return _baseFee(_marketKey);
    }

    /*
     * The fee charged when opening a position on the heavy side of a market using next price mechanism.
     */
    function baseFeeNextPrice(bytes32 _marketKey) external view returns (uint256) {
        return _baseFeeNextPrice(_marketKey);
    }

    /*
     * The number of price update rounds during which confirming next-price is allowed
     */
    function nextPriceConfirmWindow(bytes32 _marketKey) public view returns (uint256) {
        return _nextPriceConfirmWindow(_marketKey);
    }

    /*
     * The maximum allowable leverage in a market.
     */
    function maxLeverage(bytes32 _marketKey) public view returns (uint256) {
        return _maxLeverage(_marketKey);
    }

    /*
     * The maximum allowable notional value on each side of a market.
     */
    function maxSingleSideValueUSD(bytes32 _marketKey) public view returns (uint256) {
        return _maxSingleSideValueUSD(_marketKey);
    }

    /*
     * The maximum theoretical funding rate per day charged by a market.
     */
    function maxFundingRate(bytes32 _marketKey) public view returns (uint256) {
        return _maxFundingRate(_marketKey);
    }

    /*
     * The skew level at which the max funding rate will be charged.
     */
    function skewScaleUSD(bytes32 _marketKey) public view returns (uint256) {
        return _skewScaleUSD(_marketKey);
    }

    function parameters(bytes32 _marketKey)
        external
        view
        returns (
            uint256 baseFee,
            uint256 baseFeeNextPrice,
            uint256 nextPriceConfirmWindow,
            uint256 maxLeverage,
            uint256 maxSingleSideValueUSD,
            uint256 maxFundingRate,
            uint256 skewScaleUSD
        )
    {
        baseFee = _baseFee(_marketKey);
        baseFeeNextPrice = _baseFeeNextPrice(_marketKey);
        nextPriceConfirmWindow = _nextPriceConfirmWindow(_marketKey);
        maxLeverage = _maxLeverage(_marketKey);
        maxSingleSideValueUSD = _maxSingleSideValueUSD(_marketKey);
        maxFundingRate = _maxFundingRate(_marketKey);
        skewScaleUSD = _skewScaleUSD(_marketKey);
    }

    /*
     * The minimum amount of sUSD paid to a liquidator when they successfully liquidate a position.
     * This quantity must be no greater than `minInitialMargin`.
     */
    function minKeeperFee() external view returns (uint256) {
        return _minKeeperFee();
    }

    /*
     * Liquidation fee basis points paid to liquidator.
     * Use together with minKeeperFee() to calculate the actual fee paid.
     */
    function liquidationFeeRatio() external view returns (uint256) {
        return _liquidationFeeRatio();
    }

    /*
     * Liquidation price buffer in basis points to prevent negative margin on liquidation.
     */
    function liquidationBufferRatio() external view returns (uint256) {
        return _liquidationBufferRatio();
    }

    /*
     * The minimum margin required to open a position.
     * This quantity must be no less than `minKeeperFee`.
     */
    function minInitialMargin() external view returns (uint256) {
        return _minInitialMargin();
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /* ---------- Setters --------- */

    function _setParameter(
        bytes32 _marketKey,
        bytes32 key,
        uint256 value
    ) internal {
        _flexibleStorage().setUIntValue(SETTING_CONTRACT_NAME, keccak256(abi.encodePacked(_marketKey, key)), value);
        emit ParameterUpdated(_marketKey, key, value);
    }

    function setBaseFee(bytes32 _marketKey, uint256 _baseFee) public onlyOwner {
        require(_baseFee <= 1e18, "taker fee greater than 1");
        _setParameter(_marketKey, PARAMETER_BASE_FEE, _baseFee);
    }

    function setBaseFeeNextPrice(bytes32 _marketKey, uint256 _baseFeeNextPrice) public onlyOwner {
        require(_baseFeeNextPrice <= 1e18, "taker fee greater than 1");
        _setParameter(_marketKey, PARAMETER_BASE_FEE_NEXT_PRICE, _baseFeeNextPrice);
    }

    function setNextPriceConfirmWindow(bytes32 _marketKey, uint256 _nextPriceConfirmWindow) public onlyOwner {
        _setParameter(_marketKey, PARAMETER_NEXT_PRICE_CONFIRM_WINDOW, _nextPriceConfirmWindow);
    }

    function setMaxLeverage(bytes32 _marketKey, uint256 _maxLeverage) public onlyOwner {
        _setParameter(_marketKey, PARAMETER_MAX_LEVERAGE, _maxLeverage);
    }

    function setMaxSingleSideValueUSD(bytes32 _marketKey, uint256 _maxSingleSideValueUSD) public onlyOwner {
        _setParameter(_marketKey, PARAMETER_MAX_SINGLE_SIDE_VALUE, _maxSingleSideValueUSD);
    }

    // Before altering parameters relevant to funding rates, outstanding funding on the underlying market
    // must be recomputed, otherwise already-accrued but unrealised funding in the market can change.

    function _recomputeFunding(bytes32 _marketKey) internal {
        IPerpsV2Market market = IPerpsV2Market(_futuresMarketManager().marketForKey(_marketKey));
        if (market.marketSize() > 0) {
            // only recompute funding when market has positions, this check is important for initial setup
            market.recomputeFunding();
        }
    }

    function setMaxFundingRate(bytes32 _marketKey, uint256 _maxFundingRate) public onlyOwner {
        _recomputeFunding(_marketKey);
        _setParameter(_marketKey, PARAMETER_MAX_FUNDING_RATE, _maxFundingRate);
    }

    function setSkewScaleUSD(bytes32 _marketKey, uint256 _skewScaleUSD) public onlyOwner {
        require(_skewScaleUSD > 0, "cannot set skew scale 0");
        _recomputeFunding(_marketKey);
        _setParameter(_marketKey, PARAMETER_MIN_SKEW_SCALE, _skewScaleUSD);
    }

    function setParameters(
        bytes32 _marketKey,
        uint256 _baseFee,
        uint256 _baseFeeNextPrice,
        uint256 _nextPriceConfirmWindow,
        uint256 _maxLeverage,
        uint256 _maxSingleSideValueUSD,
        uint256 _maxFundingRate,
        uint256 _skewScaleUSD
    ) external onlyOwner {
        _recomputeFunding(_marketKey);
        setBaseFee(_marketKey, _baseFee);
        setBaseFeeNextPrice(_marketKey, _baseFeeNextPrice);
        setNextPriceConfirmWindow(_marketKey, _nextPriceConfirmWindow);
        setMaxLeverage(_marketKey, _maxLeverage);
        setMaxSingleSideValueUSD(_marketKey, _maxSingleSideValueUSD);
        setMaxFundingRate(_marketKey, _maxFundingRate);
        setSkewScaleUSD(_marketKey, _skewScaleUSD);
    }

    function setMinKeeperFee(uint256 _sUSD) external onlyOwner {
        require(_sUSD <= _minInitialMargin(), "min margin < liquidation fee");
        _flexibleStorage().setUIntValue(SETTING_CONTRACT_NAME, SETTING_MIN_KEEPER_FEE, _sUSD);
        emit MinKeeperFeeUpdated(_sUSD);
    }

    function setLiquidationFeeRatio(uint256 _ratio) external onlyOwner {
        _flexibleStorage().setUIntValue(SETTING_CONTRACT_NAME, SETTING_LIQUIDATION_FEE_RATIO, _ratio);
        emit LiquidationFeeRatioUpdated(_ratio);
    }

    function setLiquidationBufferRatio(uint256 _ratio) external onlyOwner {
        _flexibleStorage().setUIntValue(SETTING_CONTRACT_NAME, SETTING_LIQUIDATION_BUFFER_RATIO, _ratio);
        emit LiquidationBufferRatioUpdated(_ratio);
    }

    function setMinInitialMargin(uint256 _minMargin) external onlyOwner {
        require(_minKeeperFee() <= _minMargin, "min margin < liquidation fee");
        _flexibleStorage().setUIntValue(SETTING_CONTRACT_NAME, SETTING_MIN_INITIAL_MARGIN, _minMargin);
        emit MinInitialMarginUpdated(_minMargin);
    }

    /* ========== EVENTS ========== */

    event ParameterUpdated(bytes32 indexed marketKey, bytes32 indexed parameter, uint256 value);
    event MinKeeperFeeUpdated(uint256 sUSD);
    event LiquidationFeeRatioUpdated(uint256 bps);
    event LiquidationBufferRatioUpdated(uint256 bps);
    event MinInitialMarginUpdated(uint256 minMargin);
}
