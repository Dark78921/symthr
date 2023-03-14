pragma solidity ^0.5.16;

// Inheritance
import "./Owned.sol";
import "./Pausable.sol";
import "./MixinResolver.sol";
import "./interfaces/ICollateralManager.sol";

// Libraries
import "./AddressSetLib.sol";
import "./Bytes32SetLib.sol";
import "./SafeDecimalMath.sol";

// Internal references
import "./CollateralManagerState.sol";
import "./interfaces/IIssuer.sol";
import "./interfaces/IExchangeRates.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/ISynth.sol";

contract CollateralManager is ICollateralManager, Owned, Pausable, MixinResolver {
    /* ========== LIBRARIES ========== */
    using SafeMath for uint256;
    using SafeDecimalMath for uint256;
    using AddressSetLib for AddressSetLib.AddressSet;
    using Bytes32SetLib for Bytes32SetLib.Bytes32Set;

    /* ========== CONSTANTS ========== */

    bytes32 private constant sUSD = "sUSD";

    uint256 private constant SECONDS_IN_A_YEAR = 31556926 * 1e18;

    // Flexible storage names
    bytes32 public constant CONTRACT_NAME = "CollateralManager";
    bytes32 internal constant COLLATERAL_SYNTHS = "collateralSynth";

    /* ========== STATE VARIABLES ========== */

    // Stores debt balances and borrow rates.
    CollateralManagerState public state;

    // The set of all collateral contracts.
    AddressSetLib.AddressSet internal _collaterals;

    // The set of all available currency keys.
    Bytes32SetLib.Bytes32Set internal _currencyKeys;

    // The set of all synths issuable by the various collateral contracts
    Bytes32SetLib.Bytes32Set internal _synths;

    // Map from currency key to synth contract name.
    mapping(bytes32 => bytes32) public synthsByKey;

    // The set of all synths that are shortable.
    Bytes32SetLib.Bytes32Set internal _shortableSynths;

    mapping(bytes32 => bytes32) public shortableSynthsByKey;

    // The factor that will scale the utilisation ratio.
    uint256 public utilisationMultiplier = 1e18;

    // The maximum amount of debt in sUSD that can be issued by non snx collateral.
    uint256 public maxDebt;

    // The rate that determines the skew limit maximum.
    uint256 public maxSkewRate;

    // The base interest rate applied to all borrows.
    uint256 public baseBorrowRate;

    // The base interest rate applied to all shorts.
    uint256 public baseShortRate;

    /* ---------- Address Resolver Configuration ---------- */

    bytes32 private constant CONTRACT_ISSUER = "Issuer";
    bytes32 private constant CONTRACT_EXRATES = "ExchangeRates";

    bytes32[24] private addressesToCache = [CONTRACT_ISSUER, CONTRACT_EXRATES];

    /* ========== CONSTRUCTOR ========== */
    constructor(
        CollateralManagerState _state,
        address _owner,
        address _resolver,
        uint256 _maxDebt,
        uint256 _maxSkewRate,
        uint256 _baseBorrowRate,
        uint256 _baseShortRate
    ) public Owned(_owner) Pausable() MixinResolver(_resolver) {
        owner = msg.sender;
        state = _state;

        setMaxDebt(_maxDebt);
        setMaxSkewRate(_maxSkewRate);
        setBaseBorrowRate(_baseBorrowRate);
        setBaseShortRate(_baseShortRate);

        owner = _owner;
    }

    /* ========== VIEWS ========== */

    function resolverAddressesRequired() public view returns (bytes32[] memory addresses) {
        bytes32[] memory staticAddresses = new bytes32[](2);
        staticAddresses[0] = CONTRACT_ISSUER;
        staticAddresses[1] = CONTRACT_EXRATES;

        bytes32[] memory shortAddresses;
        uint256 length = _shortableSynths.elements.length;

        if (length > 0) {
            shortAddresses = new bytes32[](length);

            for (uint256 i = 0; i < length; i++) {
                shortAddresses[i] = _shortableSynths.elements[i];
            }
        }

        bytes32[] memory synthAddresses = combineArrays(shortAddresses, _synths.elements);

        if (synthAddresses.length > 0) {
            addresses = combineArrays(synthAddresses, staticAddresses);
        } else {
            addresses = staticAddresses;
        }
    }

    // helper function to check whether synth "by key" is a collateral issued by multi-collateral
    function isSynthManaged(bytes32 currencyKey) external view returns (bool) {
        return synthsByKey[currencyKey] != bytes32(0);
    }

    /* ---------- Related Contracts ---------- */

    function _issuer() internal view returns (IIssuer) {
        return IIssuer(requireAndGetAddress(CONTRACT_ISSUER));
    }

    function _exchangeRates() internal view returns (IExchangeRates) {
        return IExchangeRates(requireAndGetAddress(CONTRACT_EXRATES));
    }

    function _synth(bytes32 synthName) internal view returns (ISynth) {
        return ISynth(requireAndGetAddress(synthName));
    }

    /* ---------- Manager Information ---------- */

    function hasCollateral(address collateral) public view returns (bool) {
        return _collaterals.contains(collateral);
    }

    function hasAllCollaterals(address[] memory collaterals) public view returns (bool) {
        for (uint256 i = 0; i < collaterals.length; i++) {
            if (!hasCollateral(collaterals[i])) {
                return false;
            }
        }
        return true;
    }

    /* ---------- State Information ---------- */

    function long(bytes32 synth) external view returns (uint256 amount) {
        return state.long(synth);
    }

    function short(bytes32 synth) external view returns (uint256 amount) {
        return state.short(synth);
    }

    function totalLong() public view returns (uint256 susdValue, bool anyRateIsInvalid) {
        bytes32[] memory synths = _currencyKeys.elements;

        if (synths.length > 0) {
            for (uint256 i = 0; i < synths.length; i++) {
                bytes32 synth = synths[i];
                if (synth == sUSD) {
                    susdValue = susdValue.add(state.long(synth));
                } else {
                    (uint256 rate, bool invalid) = _exchangeRates().rateAndInvalid(synth);
                    uint256 amount = state.long(synth).multiplyDecimal(rate);
                    susdValue = susdValue.add(amount);
                    if (invalid) {
                        anyRateIsInvalid = true;
                    }
                }
            }
        }
    }

    function totalShort() public view returns (uint256 susdValue, bool anyRateIsInvalid) {
        bytes32[] memory synths = _shortableSynths.elements;

        if (synths.length > 0) {
            for (uint256 i = 0; i < synths.length; i++) {
                bytes32 synth = _synth(synths[i]).currencyKey();
                (uint256 rate, bool invalid) = _exchangeRates().rateAndInvalid(synth);
                uint256 amount = state.short(synth).multiplyDecimal(rate);
                susdValue = susdValue.add(amount);
                if (invalid) {
                    anyRateIsInvalid = true;
                }
            }
        }
    }

    function totalLongAndShort() public view returns (uint256 susdValue, bool anyRateIsInvalid) {
        bytes32[] memory currencyKeys = _currencyKeys.elements;

        if (currencyKeys.length > 0) {
            (uint256[] memory rates, bool invalid) = _exchangeRates().ratesAndInvalidForCurrencies(currencyKeys);
            for (uint256 i = 0; i < rates.length; i++) {
                uint256 longAmount = state.long(currencyKeys[i]).multiplyDecimal(rates[i]);
                uint256 shortAmount = state.short(currencyKeys[i]).multiplyDecimal(rates[i]);
                susdValue = susdValue.add(longAmount).add(shortAmount);
                if (invalid) {
                    anyRateIsInvalid = true;
                }
            }
        }
    }

    function getBorrowRate() public view returns (uint256 borrowRate, bool anyRateIsInvalid) {
        // get the snx backed debt.
        uint256 snxDebt = _issuer().totalIssuedSynths(sUSD, true);

        // now get the non snx backed debt.
        (uint256 nonSnxDebt, bool ratesInvalid) = totalLong();

        // the total.
        uint256 totalDebt = snxDebt.add(nonSnxDebt);

        // now work out the utilisation ratio, and divide through to get a per second value.
        uint256 utilisation = nonSnxDebt.divideDecimal(totalDebt).divideDecimal(SECONDS_IN_A_YEAR);

        // scale it by the utilisation multiplier.
        uint256 scaledUtilisation = utilisation.multiplyDecimal(utilisationMultiplier);

        // finally, add the base borrow rate.
        borrowRate = scaledUtilisation.add(baseBorrowRate);

        anyRateIsInvalid = ratesInvalid;
    }

    function getShortRate(bytes32 synthKey) public view returns (uint256 shortRate, bool rateIsInvalid) {
        rateIsInvalid = _exchangeRates().rateIsInvalid(synthKey);

        // Get the long and short supply.
        uint256 longSupply = IERC20(address(_synth(shortableSynthsByKey[synthKey]))).totalSupply();
        uint256 shortSupply = state.short(synthKey);

        // In this case, the market is skewed long so its free to short.
        if (longSupply > shortSupply) {
            return (0, rateIsInvalid);
        }

        // Otherwise workout the skew towards the short side.
        uint256 skew = shortSupply.sub(longSupply);

        // Divide through by the size of the market.
        uint256 proportionalSkew = skew.divideDecimal(longSupply.add(shortSupply)).divideDecimal(SECONDS_IN_A_YEAR);

        // Enforce a skew limit maximum.
        uint256 maxSkewLimit = proportionalSkew.multiplyDecimal(maxSkewRate);

        // Finally, add the base short rate.
        shortRate = maxSkewLimit.add(baseShortRate);
    }

    function getRatesAndTime(uint256 index)
        public
        view
        returns (
            uint256 entryRate,
            uint256 lastRate,
            uint256 lastUpdated,
            uint256 newIndex
        )
    {
        (entryRate, lastRate, lastUpdated, newIndex) = state.getRatesAndTime(index);
    }

    function getShortRatesAndTime(bytes32 currency, uint256 index)
        public
        view
        returns (
            uint256 entryRate,
            uint256 lastRate,
            uint256 lastUpdated,
            uint256 newIndex
        )
    {
        (entryRate, lastRate, lastUpdated, newIndex) = state.getShortRatesAndTime(currency, index);
    }

    function exceedsDebtLimit(uint256 amount, bytes32 currency) external view returns (bool canIssue, bool anyRateIsInvalid) {
        uint256 usdAmount = _exchangeRates().effectiveValue(currency, amount, sUSD);

        (uint256 longAndShortValue, bool invalid) = totalLongAndShort();

        return (longAndShortValue.add(usdAmount) <= maxDebt, invalid);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /* ---------- SETTERS ---------- */

    function setUtilisationMultiplier(uint256 _utilisationMultiplier) public onlyOwner {
        require(_utilisationMultiplier > 0, "Must be greater than 0");
        utilisationMultiplier = _utilisationMultiplier;
        emit UtilisationMultiplierUpdated(utilisationMultiplier);
    }

    function setMaxDebt(uint256 _maxDebt) public onlyOwner {
        require(_maxDebt > 0, "Must be greater than 0");
        maxDebt = _maxDebt;
        emit MaxDebtUpdated(maxDebt);
    }

    function setMaxSkewRate(uint256 _maxSkewRate) public onlyOwner {
        maxSkewRate = _maxSkewRate;
        emit MaxSkewRateUpdated(maxSkewRate);
    }

    function setBaseBorrowRate(uint256 _baseBorrowRate) public onlyOwner {
        baseBorrowRate = _baseBorrowRate;
        emit BaseBorrowRateUpdated(baseBorrowRate);
    }

    function setBaseShortRate(uint256 _baseShortRate) public onlyOwner {
        baseShortRate = _baseShortRate;
        emit BaseShortRateUpdated(baseShortRate);
    }

    /* ---------- LOANS ---------- */

    function getNewLoanId() external onlyCollateral returns (uint256 id) {
        id = state.incrementTotalLoans();
    }

    /* ---------- MANAGER ---------- */

    function addCollaterals(address[] calldata collaterals) external onlyOwner {
        for (uint256 i = 0; i < collaterals.length; i++) {
            if (!_collaterals.contains(collaterals[i])) {
                _collaterals.add(collaterals[i]);
                emit CollateralAdded(collaterals[i]);
            }
        }
    }

    function removeCollaterals(address[] calldata collaterals) external onlyOwner {
        for (uint256 i = 0; i < collaterals.length; i++) {
            if (_collaterals.contains(collaterals[i])) {
                _collaterals.remove(collaterals[i]);
                emit CollateralRemoved(collaterals[i]);
            }
        }
    }

    function addSynths(bytes32[] calldata synthNamesInResolver, bytes32[] calldata synthKeys) external onlyOwner {
        require(synthNamesInResolver.length == synthKeys.length, "Input array length mismatch");

        for (uint256 i = 0; i < synthNamesInResolver.length; i++) {
            if (!_synths.contains(synthNamesInResolver[i])) {
                bytes32 synthName = synthNamesInResolver[i];
                _synths.add(synthName);
                _currencyKeys.add(synthKeys[i]);
                synthsByKey[synthKeys[i]] = synthName;
                emit SynthAdded(synthName);
            }
        }

        rebuildCache();
    }

    function areSynthsAndCurrenciesSet(bytes32[] calldata requiredSynthNamesInResolver, bytes32[] calldata synthKeys)
        external
        view
        returns (bool)
    {
        if (_synths.elements.length != requiredSynthNamesInResolver.length) {
            return false;
        }

        for (uint256 i = 0; i < requiredSynthNamesInResolver.length; i++) {
            if (!_synths.contains(requiredSynthNamesInResolver[i])) {
                return false;
            }
            if (synthsByKey[synthKeys[i]] != requiredSynthNamesInResolver[i]) {
                return false;
            }
        }

        return true;
    }

    function removeSynths(bytes32[] calldata synthNamesInResolver, bytes32[] calldata synthKeys) external onlyOwner {
        require(synthNamesInResolver.length == synthKeys.length, "Input array length mismatch");

        for (uint256 i = 0; i < synthNamesInResolver.length; i++) {
            if (_synths.contains(synthNamesInResolver[i])) {
                // Remove it from the the address set lib.
                _synths.remove(synthNamesInResolver[i]);
                _currencyKeys.remove(synthKeys[i]);
                delete synthsByKey[synthKeys[i]];

                emit SynthRemoved(synthNamesInResolver[i]);
            }
        }
    }

    function addShortableSynths(bytes32[] calldata requiredSynthNamesInResolver, bytes32[] calldata synthKeys)
        external
        onlyOwner
    {
        require(requiredSynthNamesInResolver.length == synthKeys.length, "Input array length mismatch");

        for (uint256 i = 0; i < requiredSynthNamesInResolver.length; i++) {
            bytes32 synth = requiredSynthNamesInResolver[i];

            if (!_shortableSynths.contains(synth)) {
                // Add it to the address set lib.
                _shortableSynths.add(synth);

                shortableSynthsByKey[synthKeys[i]] = synth;

                emit ShortableSynthAdded(synth);

                // now the associated synth key to the CollateralManagerState
                state.addShortCurrency(synthKeys[i]);
            }
        }

        rebuildCache();
    }

    function areShortableSynthsSet(bytes32[] calldata requiredSynthNamesInResolver, bytes32[] calldata synthKeys)
        external
        view
        returns (bool)
    {
        require(requiredSynthNamesInResolver.length == synthKeys.length, "Input array length mismatch");

        if (_shortableSynths.elements.length != requiredSynthNamesInResolver.length) {
            return false;
        }

        // now check everything added to external state contract
        for (uint256 i = 0; i < synthKeys.length; i++) {
            if (state.getShortRatesLength(synthKeys[i]) == 0) {
                return false;
            }
        }

        return true;
    }

    function removeShortableSynths(bytes32[] calldata synths) external onlyOwner {
        for (uint256 i = 0; i < synths.length; i++) {
            if (_shortableSynths.contains(synths[i])) {
                // Remove it from the the address set lib.
                _shortableSynths.remove(synths[i]);

                bytes32 synthKey = _synth(synths[i]).currencyKey();

                delete shortableSynthsByKey[synthKey];

                state.removeShortCurrency(synthKey);

                emit ShortableSynthRemoved(synths[i]);
            }
        }
    }

    /* ---------- STATE MUTATIONS ---------- */

    function updateBorrowRates(uint256 rate) internal {
        state.updateBorrowRates(rate);
    }

    function updateShortRates(bytes32 currency, uint256 rate) internal {
        state.updateShortRates(currency, rate);
    }

    function updateBorrowRatesCollateral(uint256 rate) external onlyCollateral {
        state.updateBorrowRates(rate);
    }

    function updateShortRatesCollateral(bytes32 currency, uint256 rate) external onlyCollateral {
        state.updateShortRates(currency, rate);
    }

    function incrementLongs(bytes32 synth, uint256 amount) external onlyCollateral {
        state.incrementLongs(synth, amount);
    }

    function decrementLongs(bytes32 synth, uint256 amount) external onlyCollateral {
        state.decrementLongs(synth, amount);
    }

    function incrementShorts(bytes32 synth, uint256 amount) external onlyCollateral {
        state.incrementShorts(synth, amount);
    }

    function decrementShorts(bytes32 synth, uint256 amount) external onlyCollateral {
        state.decrementShorts(synth, amount);
    }

    function accrueInterest(
        uint256 interestIndex,
        bytes32 currency,
        bool isShort
    ) external onlyCollateral returns (uint256 difference, uint256 index) {
        // 1. Get the rates we need.
        (uint256 entryRate, uint256 lastRate, uint256 lastUpdated, uint256 newIndex) = isShort
            ? getShortRatesAndTime(currency, interestIndex)
            : getRatesAndTime(interestIndex);

        // 2. Get the instantaneous rate.
        (uint256 rate, bool invalid) = isShort ? getShortRate(currency) : getBorrowRate();

        require(!invalid, "Invalid rate");

        // 3. Get the time since we last updated the rate.
        // TODO: consider this in the context of l2 time.
        uint256 timeDelta = block.timestamp.sub(lastUpdated).mul(1e18);

        // 4. Get the latest cumulative rate. F_n+1 = F_n + F_last
        uint256 latestCumulative = lastRate.add(rate.multiplyDecimal(timeDelta));

        // 5. Return the rate differential and the new interest index.
        difference = latestCumulative.sub(entryRate);
        index = newIndex;

        // 5. Update rates with the lastest cumulative rate. This also updates the time.
        isShort ? updateShortRates(currency, latestCumulative) : updateBorrowRates(latestCumulative);
    }

    /* ========== MODIFIERS ========== */

    modifier onlyCollateral() {
        bool isMultiCollateral = hasCollateral(msg.sender);

        require(isMultiCollateral, "Only collateral contracts");
        _;
    }

    // ========== EVENTS ==========
    event MaxDebtUpdated(uint256 maxDebt);
    event MaxSkewRateUpdated(uint256 maxSkewRate);
    event LiquidationPenaltyUpdated(uint256 liquidationPenalty);
    event BaseBorrowRateUpdated(uint256 baseBorrowRate);
    event BaseShortRateUpdated(uint256 baseShortRate);
    event UtilisationMultiplierUpdated(uint256 utilisationMultiplier);

    event CollateralAdded(address collateral);
    event CollateralRemoved(address collateral);

    event SynthAdded(bytes32 synth);
    event SynthRemoved(bytes32 synth);

    event ShortableSynthAdded(bytes32 synth);
    event ShortableSynthRemoved(bytes32 synth);
}
