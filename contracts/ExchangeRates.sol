pragma solidity ^0.5.16;

// Inheritance
import "./Owned.sol";
import "./MixinSystemSettings.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IExchangeRates.sol";

// Libraries
import "./SafeDecimalMath.sol";

// Internal references
// AggregatorInterface from Chainlink represents a decentralized pricing network for a single currency key
import "@chainlink/contracts-0.0.10/src/v0.5/interfaces/AggregatorV2V3Interface.sol";
// FlagsInterface from Chainlink addresses SIP-76
import "@chainlink/contracts-0.0.10/src/v0.5/interfaces/FlagsInterface.sol";
import "./interfaces/IExchangeCircuitBreaker.sol";

// https://docs.synthetix.io/contracts/source/contracts/exchangerates
contract ExchangeRates is Owned, MixinSystemSettings, IExchangeRates {
    using SafeMath for uint256;
    using SafeDecimalMath for uint256;

    bytes32 public constant CONTRACT_NAME = "ExchangeRates";
    //slither-disable-next-line naming-convention
    bytes32 internal constant sUSD = "sUSD";

    // Decentralized oracle networks that feed into pricing aggregators
    mapping(bytes32 => AggregatorV2V3Interface) public aggregators;

    mapping(bytes32 => uint8) public currencyKeyDecimals;

    // List of aggregator keys for convenient iteration
    bytes32[] public aggregatorKeys;

    // ========== CONSTRUCTOR ==========

    constructor(address _owner, address _resolver) public Owned(_owner) MixinSystemSettings(_resolver) {}

    /* ========== MUTATIVE FUNCTIONS ========== */

    function addAggregator(bytes32 currencyKey, address aggregatorAddress) external onlyOwner {
        AggregatorV2V3Interface aggregator = AggregatorV2V3Interface(aggregatorAddress);
        // This check tries to make sure that a valid aggregator is being added.
        // It checks if the aggregator is an existing smart contract that has implemented `latestTimestamp` function.

        require(aggregator.latestRound() >= 0, "Given Aggregator is invalid");
        uint8 decimals = aggregator.decimals();
        require(decimals <= 18, "Aggregator decimals should be lower or equal to 18");
        if (address(aggregators[currencyKey]) == address(0)) {
            aggregatorKeys.push(currencyKey);
        }
        aggregators[currencyKey] = aggregator;
        currencyKeyDecimals[currencyKey] = decimals;
        emit AggregatorAdded(currencyKey, address(aggregator));
    }

    function removeAggregator(bytes32 currencyKey) external onlyOwner {
        address aggregator = address(aggregators[currencyKey]);
        require(aggregator != address(0), "No aggregator exists for key");
        delete aggregators[currencyKey];
        delete currencyKeyDecimals[currencyKey];

        bool wasRemoved = removeFromArray(currencyKey, aggregatorKeys);

        if (wasRemoved) {
            emit AggregatorRemoved(currencyKey, aggregator);
        }
    }

    /* ========== VIEWS ========== */

    function currenciesUsingAggregator(address aggregator) external view returns (bytes32[] memory currencies) {
        uint256 count = 0;
        currencies = new bytes32[](aggregatorKeys.length);
        for (uint256 i = 0; i < aggregatorKeys.length; i++) {
            bytes32 currencyKey = aggregatorKeys[i];
            if (address(aggregators[currencyKey]) == aggregator) {
                currencies[count++] = currencyKey;
            }
        }
    }

    function rateStalePeriod() external view returns (uint256) {
        return getRateStalePeriod();
    }

    function aggregatorWarningFlags() external view returns (address) {
        return getAggregatorWarningFlags();
    }

    function rateAndUpdatedTime(bytes32 currencyKey) external view returns (uint256 rate, uint256 time) {
        RateAndUpdatedTime memory rateAndTime = _getRateAndUpdatedTime(currencyKey);
        return (rateAndTime.rate, rateAndTime.time);
    }

    function getLastRoundIdBeforeElapsedSecs(
        bytes32 currencyKey,
        uint256 startingRoundId,
        uint256 startingTimestamp,
        uint256 timediff
    ) external view returns (uint256) {
        uint256 roundId = startingRoundId;
        uint256 nextTimestamp = 0;
        while (true) {
            (, nextTimestamp) = _getRateAndTimestampAtRound(currencyKey, roundId + 1);
            // if there's no new round, then the previous roundId was the latest
            if (nextTimestamp == 0 || nextTimestamp > startingTimestamp + timediff) {
                return roundId;
            }
            roundId++;
        }
        return roundId;
    }

    function getCurrentRoundId(bytes32 currencyKey) external view returns (uint256) {
        return _getCurrentRoundId(currencyKey);
    }

    function effectiveValueAndRatesAtRound(
        bytes32 sourceCurrencyKey,
        uint256 sourceAmount,
        bytes32 destinationCurrencyKey,
        uint256 roundIdForSrc,
        uint256 roundIdForDest
    )
        external
        view
        returns (
            uint256 value,
            uint256 sourceRate,
            uint256 destinationRate
        )
    {
        (sourceRate, ) = _getRateAndTimestampAtRound(sourceCurrencyKey, roundIdForSrc);
        // If there's no change in the currency, then just return the amount they gave us
        if (sourceCurrencyKey == destinationCurrencyKey) {
            destinationRate = sourceRate;
            value = sourceAmount;
        } else {
            (destinationRate, ) = _getRateAndTimestampAtRound(destinationCurrencyKey, roundIdForDest);
            // prevent divide-by 0 error (this happens if the dest is not a valid rate)
            if (destinationRate > 0) {
                // Calculate the effective value by going from source -> USD -> destination
                value = sourceAmount.multiplyDecimalRound(sourceRate).divideDecimalRound(destinationRate);
            }
        }
    }

    function rateAndTimestampAtRound(bytes32 currencyKey, uint256 roundId) external view returns (uint256 rate, uint256 time) {
        return _getRateAndTimestampAtRound(currencyKey, roundId);
    }

    function lastRateUpdateTimes(bytes32 currencyKey) external view returns (uint256) {
        return _getUpdatedTime(currencyKey);
    }

    function lastRateUpdateTimesForCurrencies(bytes32[] calldata currencyKeys) external view returns (uint256[] memory) {
        uint256[] memory lastUpdateTimes = new uint256[](currencyKeys.length);

        for (uint256 i = 0; i < currencyKeys.length; i++) {
            lastUpdateTimes[i] = _getUpdatedTime(currencyKeys[i]);
        }

        return lastUpdateTimes;
    }

    function effectiveValue(
        bytes32 sourceCurrencyKey,
        uint256 sourceAmount,
        bytes32 destinationCurrencyKey
    ) external view returns (uint256 value) {
        (value, , ) = _effectiveValueAndRates(sourceCurrencyKey, sourceAmount, destinationCurrencyKey);
    }

    function effectiveValueAndRates(
        bytes32 sourceCurrencyKey,
        uint256 sourceAmount,
        bytes32 destinationCurrencyKey
    )
        external
        view
        returns (
            uint256 value,
            uint256 sourceRate,
            uint256 destinationRate
        )
    {
        return _effectiveValueAndRates(sourceCurrencyKey, sourceAmount, destinationCurrencyKey);
    }

    // SIP-120 Atomic exchanges
    function effectiveAtomicValueAndRates(
        bytes32,
        uint256,
        bytes32
    )
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        _notImplemented();
    }

    function rateForCurrency(bytes32 currencyKey) external view returns (uint256) {
        return _getRateAndUpdatedTime(currencyKey).rate;
    }

    /// @notice getting N rounds of rates for a currency at a specific round
    /// @param currencyKey the currency key
    /// @param numRounds the number of rounds to get
    /// @param roundId the round id
    /// @return a list of rates and a list of times
    function ratesAndUpdatedTimeForCurrencyLastNRounds(
        bytes32 currencyKey,
        uint256 numRounds,
        uint256 roundId
    ) external view returns (uint256[] memory rates, uint256[] memory times) {
        rates = new uint256[](numRounds);
        times = new uint256[](numRounds);

        roundId = roundId > 0 ? roundId : _getCurrentRoundId(currencyKey);
        for (uint256 i = 0; i < numRounds; i++) {
            // fetch the rate and treat is as current, so inverse limits if frozen will always be applied
            // regardless of current rate
            (rates[i], times[i]) = _getRateAndTimestampAtRound(currencyKey, roundId);

            if (roundId == 0) {
                // if we hit the last round, then return what we have
                return (rates, times);
            } else {
                roundId--;
            }
        }
    }

    function ratesForCurrencies(bytes32[] calldata currencyKeys) external view returns (uint256[] memory) {
        uint256[] memory _localRates = new uint256[](currencyKeys.length);

        for (uint256 i = 0; i < currencyKeys.length; i++) {
            _localRates[i] = _getRate(currencyKeys[i]);
        }

        return _localRates;
    }

    function rateAndInvalid(bytes32 currencyKey) external view returns (uint256 rate, bool isInvalid) {
        RateAndUpdatedTime memory rateAndTime = _getRateAndUpdatedTime(currencyKey);

        if (currencyKey == sUSD) {
            return (rateAndTime.rate, false);
        }
        return (
            rateAndTime.rate,
            _rateIsStaleWithTime(getRateStalePeriod(), rateAndTime.time) ||
                _rateIsFlagged(currencyKey, FlagsInterface(getAggregatorWarningFlags()))
        );
    }

    function ratesAndInvalidForCurrencies(bytes32[] calldata currencyKeys)
        external
        view
        returns (uint256[] memory rates, bool anyRateInvalid)
    {
        rates = new uint256[](currencyKeys.length);

        uint256 _rateStalePeriod = getRateStalePeriod();

        // fetch all flags at once
        bool[] memory flagList = getFlagsForRates(currencyKeys);

        for (uint256 i = 0; i < currencyKeys.length; i++) {
            // do one lookup of the rate & time to minimize gas
            RateAndUpdatedTime memory rateEntry = _getRateAndUpdatedTime(currencyKeys[i]);
            rates[i] = rateEntry.rate;
            if (!anyRateInvalid && currencyKeys[i] != sUSD) {
                anyRateInvalid = flagList[i] || _rateIsStaleWithTime(_rateStalePeriod, rateEntry.time);
            }
        }
    }

    function rateIsStale(bytes32 currencyKey) external view returns (bool) {
        return _rateIsStale(currencyKey, getRateStalePeriod());
    }

    function rateIsInvalid(bytes32 currencyKey) external view returns (bool) {
        return
            _rateIsStale(currencyKey, getRateStalePeriod()) ||
            _rateIsFlagged(currencyKey, FlagsInterface(getAggregatorWarningFlags()));
    }

    function rateIsFlagged(bytes32 currencyKey) external view returns (bool) {
        return _rateIsFlagged(currencyKey, FlagsInterface(getAggregatorWarningFlags()));
    }

    function anyRateIsInvalid(bytes32[] calldata currencyKeys) external view returns (bool) {
        // Loop through each key and check whether the data point is stale.

        uint256 _rateStalePeriod = getRateStalePeriod();
        bool[] memory flagList = getFlagsForRates(currencyKeys);

        for (uint256 i = 0; i < currencyKeys.length; i++) {
            if (flagList[i] || _rateIsStale(currencyKeys[i], _rateStalePeriod)) {
                return true;
            }
        }

        return false;
    }

    /// this method checks whether any rate is:
    /// 1. flagged
    /// 2. stale with respect to current time (now)
    function anyRateIsInvalidAtRound(bytes32[] calldata currencyKeys, uint256[] calldata roundIds) external view returns (bool) {
        // Loop through each key and check whether the data point is stale.

        require(roundIds.length == currencyKeys.length, "roundIds must be the same length as currencyKeys");

        uint256 _rateStalePeriod = getRateStalePeriod();
        bool[] memory flagList = getFlagsForRates(currencyKeys);

        for (uint256 i = 0; i < currencyKeys.length; i++) {
            if (flagList[i] || _rateIsStaleAtRound(currencyKeys[i], roundIds[i], _rateStalePeriod)) {
                return true;
            }
        }

        return false;
    }

    function synthTooVolatileForAtomicExchange(bytes32) external view returns (bool) {
        _notImplemented();
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    function getFlagsForRates(bytes32[] memory currencyKeys) internal view returns (bool[] memory flagList) {
        FlagsInterface _flags = FlagsInterface(getAggregatorWarningFlags());

        // fetch all flags at once
        if (_flags != FlagsInterface(0)) {
            address[] memory _aggregators = new address[](currencyKeys.length);

            for (uint256 i = 0; i < currencyKeys.length; i++) {
                _aggregators[i] = address(aggregators[currencyKeys[i]]);
            }

            flagList = _flags.getFlags(_aggregators);
        } else {
            flagList = new bool[](currencyKeys.length);
        }
    }

    function removeFromArray(bytes32 entry, bytes32[] storage array) internal returns (bool) {
        for (uint256 i = 0; i < array.length; i++) {
            if (array[i] == entry) {
                delete array[i];

                // Copy the last key into the place of the one we just deleted
                // If there's only one key, this is array[0] = array[0].
                // If we're deleting the last one, it's also a NOOP in the same way.
                array[i] = array[array.length - 1];

                // Decrease the size of the array by one.
                array.length--;

                return true;
            }
        }
        return false;
    }

    function _formatAggregatorAnswer(bytes32 currencyKey, int256 rate) internal view returns (uint256) {
        require(rate >= 0, "Negative rate not supported");
        if (currencyKeyDecimals[currencyKey] > 0) {
            uint256 multiplier = 10**uint256(SafeMath.sub(18, currencyKeyDecimals[currencyKey]));
            return uint256(uint256(rate).mul(multiplier));
        }
        return uint256(rate);
    }

    function _getRateAndUpdatedTime(bytes32 currencyKey) internal view returns (RateAndUpdatedTime memory) {
        // sUSD rate is 1.0
        if (currencyKey == sUSD) {
            return RateAndUpdatedTime({rate: uint216(SafeDecimalMath.unit()), time: 0});
        } else {
            AggregatorV2V3Interface aggregator = aggregators[currencyKey];
            if (aggregator != AggregatorV2V3Interface(0)) {
                // this view from the aggregator is the most gas efficient but it can throw when there's no data,
                // so let's call it low-level to suppress any reverts
                bytes memory payload = abi.encodeWithSignature("latestRoundData()");
                // solhint-disable avoid-low-level-calls
                // slither-disable-next-line low-level-calls
                (bool success, bytes memory returnData) = address(aggregator).staticcall(payload);

                if (success) {
                    (, int256 answer, , uint256 updatedAt, ) = abi.decode(returnData, (uint80, int256, uint256, uint256, uint80));
                    return
                        RateAndUpdatedTime({
                            rate: uint216(_formatAggregatorAnswer(currencyKey, answer)),
                            time: uint40(updatedAt)
                        });
                } // else return defaults, to avoid reverting in views
            } // else return defaults, to avoid reverting in views
        }
    }

    function _getCurrentRoundId(bytes32 currencyKey) internal view returns (uint256) {
        if (currencyKey == sUSD) {
            return 0;
        }
        AggregatorV2V3Interface aggregator = aggregators[currencyKey];
        if (aggregator != AggregatorV2V3Interface(0)) {
            return aggregator.latestRound();
        } // else return defaults, to avoid reverting in views
    }

    function _getRateAndTimestampAtRound(bytes32 currencyKey, uint256 roundId)
        internal
        view
        returns (uint256 rate, uint256 time)
    {
        // short circuit sUSD
        if (currencyKey == sUSD) {
            // sUSD has no rounds, and 0 time is preferrable for "volatility" heuristics
            // which are used in atomic swaps and fee reclamation
            return (SafeDecimalMath.unit(), 0);
        } else {
            AggregatorV2V3Interface aggregator = aggregators[currencyKey];
            if (aggregator != AggregatorV2V3Interface(0)) {
                // this view from the aggregator is the most gas efficient but it can throw when there's no data,
                // so let's call it low-level to suppress any reverts
                bytes memory payload = abi.encodeWithSignature("getRoundData(uint80)", roundId);
                // solhint-disable avoid-low-level-calls
                (bool success, bytes memory returnData) = address(aggregator).staticcall(payload);

                if (success) {
                    (, int256 answer, , uint256 updatedAt, ) = abi.decode(returnData, (uint80, int256, uint256, uint256, uint80));
                    return (_formatAggregatorAnswer(currencyKey, answer), updatedAt);
                } // else return defaults, to avoid reverting in views
            } // else return defaults, to avoid reverting in views
        }
    }

    function _getRate(bytes32 currencyKey) internal view returns (uint256) {
        return _getRateAndUpdatedTime(currencyKey).rate;
    }

    function _getUpdatedTime(bytes32 currencyKey) internal view returns (uint256) {
        return _getRateAndUpdatedTime(currencyKey).time;
    }

    function _effectiveValueAndRates(
        bytes32 sourceCurrencyKey,
        uint256 sourceAmount,
        bytes32 destinationCurrencyKey
    )
        internal
        view
        returns (
            uint256 value,
            uint256 sourceRate,
            uint256 destinationRate
        )
    {
        sourceRate = _getRate(sourceCurrencyKey);
        // If there's no change in the currency, then just return the amount they gave us
        if (sourceCurrencyKey == destinationCurrencyKey) {
            destinationRate = sourceRate;
            value = sourceAmount;
        } else {
            // Calculate the effective value by going from source -> USD -> destination
            destinationRate = _getRate(destinationCurrencyKey);
            // prevent divide-by 0 error (this happens if the dest is not a valid rate)
            if (destinationRate > 0) {
                value = sourceAmount.multiplyDecimalRound(sourceRate).divideDecimalRound(destinationRate);
            }
        }
    }

    function _rateIsStale(bytes32 currencyKey, uint256 _rateStalePeriod) internal view returns (bool) {
        // sUSD is a special case and is never stale (check before an SLOAD of getRateAndUpdatedTime)
        if (currencyKey == sUSD) {
            return false;
        }
        return _rateIsStaleWithTime(_rateStalePeriod, _getUpdatedTime(currencyKey));
    }

    function _rateIsStaleAtRound(
        bytes32 currencyKey,
        uint256 roundId,
        uint256 _rateStalePeriod
    ) internal view returns (bool) {
        // sUSD is a special case and is never stale (check before an SLOAD of getRateAndUpdatedTime)
        if (currencyKey == sUSD) {
            return false;
        }
        (, uint256 time) = _getRateAndTimestampAtRound(currencyKey, roundId);
        return _rateIsStaleWithTime(_rateStalePeriod, time);
    }

    function _rateIsStaleWithTime(uint256 _rateStalePeriod, uint256 _time) internal view returns (bool) {
        return _time.add(_rateStalePeriod) < now;
    }

    function _rateIsFlagged(bytes32 currencyKey, FlagsInterface flags) internal view returns (bool) {
        // sUSD is a special case and is never invalid
        if (currencyKey == sUSD) {
            return false;
        }
        address aggregator = address(aggregators[currencyKey]);
        // when no aggregator or when the flags haven't been setup
        if (aggregator == address(0) || flags == FlagsInterface(0)) {
            return false;
        }
        return flags.getFlag(aggregator);
    }

    function _notImplemented() internal pure {
        // slither-disable-next-line dead-code
        revert("Cannot be run on this layer");
    }

    /* ========== EVENTS ========== */

    event AggregatorAdded(bytes32 currencyKey, address aggregator);
    event AggregatorRemoved(bytes32 currencyKey, address aggregator);
}
