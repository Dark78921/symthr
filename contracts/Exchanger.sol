pragma solidity ^0.5.16;

// Inheritance
import "./Owned.sol";
import "./MixinResolver.sol";
import "./MixinSystemSettings.sol";
import "./interfaces/IExchanger.sol";

// Libraries
import "./SafeDecimalMath.sol";

// Internal references
import "./interfaces/ISystemStatus.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IExchangeState.sol";
import "./interfaces/IExchangeRates.sol";
import "./interfaces/IExchangeCircuitBreaker.sol";
import "./interfaces/ISynthetix.sol";
import "./interfaces/IFeePool.sol";
import "./interfaces/IDelegateApprovals.sol";
import "./interfaces/IIssuer.sol";
import "./interfaces/ITradingRewards.sol";
import "./interfaces/IVirtualSynth.sol";
import "./Proxyable.sol";

// Used to have strongly-typed access to internal mutative functions in Synthetix
interface ISynthetixInternal {
    function emitExchangeTracking(
        bytes32 trackingCode,
        bytes32 toCurrencyKey,
        uint256 toAmount,
        uint256 fee
    ) external;

    function emitSynthExchange(
        address account,
        bytes32 fromCurrencyKey,
        uint256 fromAmount,
        bytes32 toCurrencyKey,
        uint256 toAmount,
        address toAddress
    ) external;

    function emitAtomicSynthExchange(
        address account,
        bytes32 fromCurrencyKey,
        uint256 fromAmount,
        bytes32 toCurrencyKey,
        uint256 toAmount,
        address toAddress
    ) external;

    function emitExchangeReclaim(
        address account,
        bytes32 currencyKey,
        uint256 amount
    ) external;

    function emitExchangeRebate(
        address account,
        bytes32 currencyKey,
        uint256 amount
    ) external;
}

interface IExchangerInternalDebtCache {
    function updateCachedSynthDebtsWithRates(bytes32[] calldata currencyKeys, uint256[] calldata currencyRates) external;

    function updateCachedSynthDebts(bytes32[] calldata currencyKeys) external;
}

// https://docs.synthetix.io/contracts/source/contracts/exchanger
contract Exchanger is Owned, MixinSystemSettings, IExchanger {
    using SafeMath for uint256;
    using SafeDecimalMath for uint256;

    bytes32 public constant CONTRACT_NAME = "Exchanger";

    bytes32 internal constant sUSD = "sUSD";

    /* ========== ADDRESS RESOLVER CONFIGURATION ========== */

    bytes32 private constant CONTRACT_SYSTEMSTATUS = "SystemStatus";
    bytes32 private constant CONTRACT_EXCHANGESTATE = "ExchangeState";
    bytes32 private constant CONTRACT_EXRATES = "ExchangeRates";
    bytes32 private constant CONTRACT_SYNTHETIX = "Synthetix";
    bytes32 private constant CONTRACT_FEEPOOL = "FeePool";
    bytes32 private constant CONTRACT_TRADING_REWARDS = "TradingRewards";
    bytes32 private constant CONTRACT_DELEGATEAPPROVALS = "DelegateApprovals";
    bytes32 private constant CONTRACT_ISSUER = "Issuer";
    bytes32 private constant CONTRACT_DEBTCACHE = "DebtCache";
    bytes32 private constant CONTRACT_CIRCUIT_BREAKER = "ExchangeCircuitBreaker";

    constructor(address _owner, address _resolver) public Owned(_owner) MixinSystemSettings(_resolver) {}

    /* ========== VIEWS ========== */

    function resolverAddressesRequired() public view returns (bytes32[] memory addresses) {
        bytes32[] memory existingAddresses = MixinSystemSettings.resolverAddressesRequired();
        bytes32[] memory newAddresses = new bytes32[](10);
        newAddresses[0] = CONTRACT_SYSTEMSTATUS;
        newAddresses[1] = CONTRACT_EXCHANGESTATE;
        newAddresses[2] = CONTRACT_EXRATES;
        newAddresses[3] = CONTRACT_SYNTHETIX;
        newAddresses[4] = CONTRACT_FEEPOOL;
        newAddresses[5] = CONTRACT_TRADING_REWARDS;
        newAddresses[6] = CONTRACT_DELEGATEAPPROVALS;
        newAddresses[7] = CONTRACT_ISSUER;
        newAddresses[8] = CONTRACT_DEBTCACHE;
        newAddresses[9] = CONTRACT_CIRCUIT_BREAKER;
        addresses = combineArrays(existingAddresses, newAddresses);
    }

    function systemStatus() internal view returns (ISystemStatus) {
        return ISystemStatus(requireAndGetAddress(CONTRACT_SYSTEMSTATUS));
    }

    function exchangeState() internal view returns (IExchangeState) {
        return IExchangeState(requireAndGetAddress(CONTRACT_EXCHANGESTATE));
    }

    function exchangeRates() internal view returns (IExchangeRates) {
        return IExchangeRates(requireAndGetAddress(CONTRACT_EXRATES));
    }

    function exchangeCircuitBreaker() internal view returns (IExchangeCircuitBreaker) {
        return IExchangeCircuitBreaker(requireAndGetAddress(CONTRACT_CIRCUIT_BREAKER));
    }

    function synthetix() internal view returns (ISynthetix) {
        return ISynthetix(requireAndGetAddress(CONTRACT_SYNTHETIX));
    }

    function feePool() internal view returns (IFeePool) {
        return IFeePool(requireAndGetAddress(CONTRACT_FEEPOOL));
    }

    function tradingRewards() internal view returns (ITradingRewards) {
        return ITradingRewards(requireAndGetAddress(CONTRACT_TRADING_REWARDS));
    }

    function delegateApprovals() internal view returns (IDelegateApprovals) {
        return IDelegateApprovals(requireAndGetAddress(CONTRACT_DELEGATEAPPROVALS));
    }

    function issuer() internal view returns (IIssuer) {
        return IIssuer(requireAndGetAddress(CONTRACT_ISSUER));
    }

    function debtCache() internal view returns (IExchangerInternalDebtCache) {
        return IExchangerInternalDebtCache(requireAndGetAddress(CONTRACT_DEBTCACHE));
    }

    function maxSecsLeftInWaitingPeriod(address account, bytes32 currencyKey) public view returns (uint256) {
        return secsLeftInWaitingPeriodForExchange(exchangeState().getMaxTimestamp(account, currencyKey));
    }

    function waitingPeriodSecs() external view returns (uint256) {
        return getWaitingPeriodSecs();
    }

    function tradingRewardsEnabled() external view returns (bool) {
        return getTradingRewardsEnabled();
    }

    function priceDeviationThresholdFactor() external view returns (uint256) {
        return getPriceDeviationThresholdFactor();
    }

    function lastExchangeRate(bytes32 currencyKey) external view returns (uint256) {
        return exchangeCircuitBreaker().lastExchangeRate(currencyKey);
    }

    function settlementOwing(address account, bytes32 currencyKey)
        public
        view
        returns (
            uint256 reclaimAmount,
            uint256 rebateAmount,
            uint256 numEntries
        )
    {
        (reclaimAmount, rebateAmount, numEntries, ) = _settlementOwing(account, currencyKey);
    }

    // Internal function to aggregate each individual rebate and reclaim entry for a synth
    function _settlementOwing(address account, bytes32 currencyKey)
        internal
        view
        returns (
            uint256 reclaimAmount,
            uint256 rebateAmount,
            uint256 numEntries,
            IExchanger.ExchangeEntrySettlement[] memory
        )
    {
        // Need to sum up all reclaim and rebate amounts for the user and the currency key
        numEntries = exchangeState().getLengthOfEntries(account, currencyKey);

        // For each unsettled exchange

        IExchanger.ExchangeEntrySettlement[] memory settlements = new IExchanger.ExchangeEntrySettlement[](numEntries);
        for (uint256 i = 0; i < numEntries; i++) {
            uint256 reclaim;
            uint256 rebate;
            // fetch the entry from storage

            IExchangeState.ExchangeEntry memory exchangeEntry = _getExchangeEntry(account, currencyKey, i);

            // determine the last round ids for src and dest pairs when period ended or latest if not over
            (uint256 srcRoundIdAtPeriodEnd, uint256 destRoundIdAtPeriodEnd) = getRoundIdsAtPeriodEnd(exchangeEntry);

            // given these round ids, determine what effective value they should have received
            (uint256 destinationAmount, , ) = exchangeRates().effectiveValueAndRatesAtRound(
                exchangeEntry.src,
                exchangeEntry.amount,
                exchangeEntry.dest,
                srcRoundIdAtPeriodEnd,
                destRoundIdAtPeriodEnd
            );

            // and deduct the fee from this amount using the exchangeFeeRate from storage
            uint256 amountShouldHaveReceived = _deductFeesFromAmount(destinationAmount, exchangeEntry.exchangeFeeRate);

            // SIP-65 settlements where the amount at end of waiting period is beyond the threshold, then
            // settle with no reclaim or rebate
            bool sip65condition = exchangeCircuitBreaker().isDeviationAboveThreshold(
                exchangeEntry.amountReceived,
                amountShouldHaveReceived
            );
            if (!sip65condition) {
                if (exchangeEntry.amountReceived > amountShouldHaveReceived) {
                    // if they received more than they should have, add to the reclaim tally
                    reclaim = exchangeEntry.amountReceived.sub(amountShouldHaveReceived);
                    reclaimAmount = reclaimAmount.add(reclaim);
                } else if (amountShouldHaveReceived > exchangeEntry.amountReceived) {
                    // if less, add to the rebate tally
                    rebate = amountShouldHaveReceived.sub(exchangeEntry.amountReceived);
                    rebateAmount = rebateAmount.add(rebate);
                }
            }

            settlements[i] = IExchanger.ExchangeEntrySettlement({
                src: exchangeEntry.src,
                amount: exchangeEntry.amount,
                dest: exchangeEntry.dest,
                reclaim: reclaim,
                rebate: rebate,
                srcRoundIdAtPeriodEnd: srcRoundIdAtPeriodEnd,
                destRoundIdAtPeriodEnd: destRoundIdAtPeriodEnd,
                timestamp: exchangeEntry.timestamp
            });
        }

        return (reclaimAmount, rebateAmount, numEntries, settlements);
    }

    function _getExchangeEntry(
        address account,
        bytes32 currencyKey,
        uint256 index
    ) internal view returns (IExchangeState.ExchangeEntry memory) {
        (
            bytes32 src,
            uint256 amount,
            bytes32 dest,
            uint256 amountReceived,
            uint256 exchangeFeeRate,
            uint256 timestamp,
            uint256 roundIdForSrc,
            uint256 roundIdForDest
        ) = exchangeState().getEntryAt(account, currencyKey, index);

        return
            IExchangeState.ExchangeEntry({
                src: src,
                amount: amount,
                dest: dest,
                amountReceived: amountReceived,
                exchangeFeeRate: exchangeFeeRate,
                timestamp: timestamp,
                roundIdForSrc: roundIdForSrc,
                roundIdForDest: roundIdForDest
            });
    }

    function hasWaitingPeriodOrSettlementOwing(address account, bytes32 currencyKey) external view returns (bool) {
        if (maxSecsLeftInWaitingPeriod(account, currencyKey) != 0) {
            return true;
        }

        (uint256 reclaimAmount, , , ) = _settlementOwing(account, currencyKey);

        return reclaimAmount > 0;
    }

    /* ========== SETTERS ========== */

    function calculateAmountAfterSettlement(
        address from,
        bytes32 currencyKey,
        uint256 amount,
        uint256 refunded
    ) public view returns (uint256 amountAfterSettlement) {
        amountAfterSettlement = amount;

        // balance of a synth will show an amount after settlement
        uint256 balanceOfSourceAfterSettlement = IERC20(address(issuer().synths(currencyKey))).balanceOf(from);

        // when there isn't enough supply (either due to reclamation settlement or because the number is too high)
        if (amountAfterSettlement > balanceOfSourceAfterSettlement) {
            // then the amount to exchange is reduced to their remaining supply
            amountAfterSettlement = balanceOfSourceAfterSettlement;
        }

        if (refunded > 0) {
            amountAfterSettlement = amountAfterSettlement.add(refunded);
        }
    }

    function isSynthRateInvalid(bytes32 currencyKey) external view returns (bool) {
        (, bool invalid) = exchangeCircuitBreaker().rateWithInvalid(currencyKey);
        return invalid;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */
    function exchange(
        address exchangeForAddress,
        address from,
        bytes32 sourceCurrencyKey,
        uint256 sourceAmount,
        bytes32 destinationCurrencyKey,
        address destinationAddress,
        bool virtualSynth,
        address rewardAddress,
        bytes32 trackingCode
    ) external onlySynthetixorSynth returns (uint256 amountReceived, IVirtualSynth vSynth) {
        uint256 fee;
        if (from != exchangeForAddress) {
            require(delegateApprovals().canExchangeFor(exchangeForAddress, from), "Not approved to act on behalf");
        }

        (amountReceived, fee, vSynth) = _exchange(
            exchangeForAddress,
            sourceCurrencyKey,
            sourceAmount,
            destinationCurrencyKey,
            destinationAddress,
            virtualSynth
        );

        _processTradingRewards(fee, rewardAddress);

        if (trackingCode != bytes32(0)) {
            _emitTrackingEvent(trackingCode, destinationCurrencyKey, amountReceived, fee);
        }
    }

    function exchangeAtomically(
        address,
        bytes32,
        uint256,
        bytes32,
        address,
        bytes32,
        uint256
    ) external returns (uint256) {
        _notImplemented();
    }

    function _emitTrackingEvent(
        bytes32 trackingCode,
        bytes32 toCurrencyKey,
        uint256 toAmount,
        uint256 fee
    ) internal {
        ISynthetixInternal(address(synthetix())).emitExchangeTracking(trackingCode, toCurrencyKey, toAmount, fee);
    }

    function _processTradingRewards(uint256 fee, address rewardAddress) internal {
        if (fee > 0 && rewardAddress != address(0) && getTradingRewardsEnabled()) {
            tradingRewards().recordExchangeFeeForAccount(fee, rewardAddress);
        }
    }

    function _updateSNXIssuedDebtOnExchange(bytes32[2] memory currencyKeys, uint256[2] memory currencyRates) internal {
        bool includesSUSD = currencyKeys[0] == sUSD || currencyKeys[1] == sUSD;
        uint256 numKeys = includesSUSD ? 2 : 3;

        bytes32[] memory keys = new bytes32[](numKeys);
        keys[0] = currencyKeys[0];
        keys[1] = currencyKeys[1];

        uint256[] memory rates = new uint256[](numKeys);
        rates[0] = currencyRates[0];
        rates[1] = currencyRates[1];

        if (!includesSUSD) {
            keys[2] = sUSD; // And we'll also update sUSD to account for any fees if it wasn't one of the exchanged currencies
            rates[2] = SafeDecimalMath.unit();
        }

        // Note that exchanges can't invalidate the debt cache, since if a rate is invalid,
        // the exchange will have failed already.
        debtCache().updateCachedSynthDebtsWithRates(keys, rates);
    }

    function _settleAndCalcSourceAmountRemaining(
        uint256 sourceAmount,
        address from,
        bytes32 sourceCurrencyKey
    ) internal returns (uint256 sourceAmountAfterSettlement) {
        (, uint256 refunded, uint256 numEntriesSettled) = _internalSettle(from, sourceCurrencyKey, false);

        sourceAmountAfterSettlement = sourceAmount;

        // when settlement was required
        if (numEntriesSettled > 0) {
            // ensure the sourceAmount takes this into account
            sourceAmountAfterSettlement = calculateAmountAfterSettlement(from, sourceCurrencyKey, sourceAmount, refunded);
        }
    }

    function _exchange(
        address from,
        bytes32 sourceCurrencyKey,
        uint256 sourceAmount,
        bytes32 destinationCurrencyKey,
        address destinationAddress,
        bool virtualSynth
    )
        internal
        returns (
            uint256 amountReceived,
            uint256 fee,
            IVirtualSynth vSynth
        )
    {
        require(sourceAmount > 0, "Zero amount");

        // Using struct to resolve stack too deep error
        IExchanger.ExchangeEntry memory entry;

        entry.roundIdForSrc = exchangeRates().getCurrentRoundId(sourceCurrencyKey);
        entry.roundIdForDest = exchangeRates().getCurrentRoundId(destinationCurrencyKey);

        uint256 sourceAmountAfterSettlement = _settleAndCalcSourceAmountRemaining(sourceAmount, from, sourceCurrencyKey);

        // If, after settlement the user has no balance left (highly unlikely), then return to prevent
        // emitting events of 0 and don't revert so as to ensure the settlement queue is emptied
        if (sourceAmountAfterSettlement == 0) {
            return (0, 0, IVirtualSynth(0));
        }

        (entry.destinationAmount, entry.sourceRate, entry.destinationRate) = exchangeRates().effectiveValueAndRatesAtRound(
            sourceCurrencyKey,
            sourceAmountAfterSettlement,
            destinationCurrencyKey,
            entry.roundIdForSrc,
            entry.roundIdForDest
        );

        _ensureCanExchangeAtRound(sourceCurrencyKey, destinationCurrencyKey, entry.roundIdForSrc, entry.roundIdForDest);

        // SIP-65: Decentralized Circuit Breaker
        // mutative call to suspend system if the rate is invalid
        if (_exchangeRatesCircuitBroken(sourceCurrencyKey, destinationCurrencyKey)) {
            return (0, 0, IVirtualSynth(0));
        }

        bool tooVolatile;
        (entry.exchangeFeeRate, tooVolatile) = _feeRateForExchangeAtRounds(
            sourceCurrencyKey,
            destinationCurrencyKey,
            entry.roundIdForSrc,
            entry.roundIdForDest
        );

        if (tooVolatile) {
            // do not exchange if rates are too volatile, this to prevent charging
            // dynamic fees that are over the max value
            return (0, 0, IVirtualSynth(0));
        }

        amountReceived = _deductFeesFromAmount(entry.destinationAmount, entry.exchangeFeeRate);
        // Note: `fee` is denominated in the destinationCurrencyKey.
        fee = entry.destinationAmount.sub(amountReceived);

        // Note: We don't need to check their balance as the _convert() below will do a safe subtraction which requires
        // the subtraction to not overflow, which would happen if their balance is not sufficient.
        vSynth = _convert(
            sourceCurrencyKey,
            from,
            sourceAmountAfterSettlement,
            destinationCurrencyKey,
            amountReceived,
            destinationAddress,
            virtualSynth
        );

        // When using a virtual synth, it becomes the destinationAddress for event and settlement tracking
        if (vSynth != IVirtualSynth(0)) {
            destinationAddress = address(vSynth);
        }

        // Remit the fee if required
        if (fee > 0) {
            // Normalize fee to sUSD
            // Note: `fee` is being reused to avoid stack too deep errors.
            fee = exchangeRates().effectiveValue(destinationCurrencyKey, fee, sUSD);

            // Remit the fee in sUSDs
            issuer().synths(sUSD).issue(feePool().FEE_ADDRESS(), fee);

            // Tell the fee pool about this
            feePool().recordFeePaid(fee);
        }

        // Note: As of this point, `fee` is denominated in sUSD.

        // Nothing changes as far as issuance data goes because the total value in the system hasn't changed.
        // But we will update the debt snapshot in case exchange rates have fluctuated since the last exchange
        // in these currencies
        _updateSNXIssuedDebtOnExchange([sourceCurrencyKey, destinationCurrencyKey], [entry.sourceRate, entry.destinationRate]);

        // Let the DApps know there was a Synth exchange
        ISynthetixInternal(address(synthetix())).emitSynthExchange(
            from,
            sourceCurrencyKey,
            sourceAmountAfterSettlement,
            destinationCurrencyKey,
            amountReceived,
            destinationAddress
        );

        // iff the waiting period is gt 0
        if (getWaitingPeriodSecs() > 0) {
            // persist the exchange information for the dest key
            appendExchange(
                destinationAddress,
                sourceCurrencyKey,
                sourceAmountAfterSettlement,
                destinationCurrencyKey,
                amountReceived,
                entry.exchangeFeeRate
            );
        }
    }

    // SIP-65: Decentralized Circuit Breaker
    function _exchangeRatesCircuitBroken(bytes32 sourceCurrencyKey, bytes32 destinationCurrencyKey)
        internal
        returns (bool circuitBroken)
    {
        // check both currencies unless they're sUSD, since its rate is never invalid (gas savings)
        if (sourceCurrencyKey != sUSD) {
            (, circuitBroken) = exchangeCircuitBreaker().rateWithBreakCircuit(sourceCurrencyKey);
        }

        if (destinationCurrencyKey != sUSD) {
            // we're not skipping the suspension check if the circuit was broken already
            // this is not terribly important, but is more consistent (so that results don't
            // depend on which synth is source and which is destination)
            bool destCircuitBroken;
            (, destCircuitBroken) = exchangeCircuitBreaker().rateWithBreakCircuit(destinationCurrencyKey);
            circuitBroken = circuitBroken || destCircuitBroken;
        }
    }

    function _convert(
        bytes32 sourceCurrencyKey,
        address from,
        uint256 sourceAmountAfterSettlement,
        bytes32 destinationCurrencyKey,
        uint256 amountReceived,
        address recipient,
        bool virtualSynth
    ) internal returns (IVirtualSynth vSynth) {
        // Burn the source amount
        issuer().synths(sourceCurrencyKey).burn(from, sourceAmountAfterSettlement);

        // Issue their new synths
        ISynth dest = issuer().synths(destinationCurrencyKey);

        if (virtualSynth) {
            Proxyable synth = Proxyable(address(dest));
            vSynth = _createVirtualSynth(IERC20(address(synth.proxy())), recipient, amountReceived, destinationCurrencyKey);
            dest.issue(address(vSynth), amountReceived);
        } else {
            dest.issue(recipient, amountReceived);
        }
    }

    function _createVirtualSynth(
        IERC20,
        address,
        uint256,
        bytes32
    ) internal returns (IVirtualSynth) {
        _notImplemented();
    }

    // Note: this function can intentionally be called by anyone on behalf of anyone else (the caller just pays the gas)
    function settle(address from, bytes32 currencyKey)
        external
        returns (
            uint256 reclaimed,
            uint256 refunded,
            uint256 numEntriesSettled
        )
    {
        systemStatus().requireSynthActive(currencyKey);
        return _internalSettle(from, currencyKey, true);
    }

    function suspendSynthWithInvalidRate(bytes32 currencyKey) external {
        systemStatus().requireSystemActive();
        // SIP-65: Decentralized Circuit Breaker
        (, bool circuitBroken) = exchangeCircuitBreaker().rateWithBreakCircuit(currencyKey);
        require(circuitBroken, "Synth price is valid");
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    function _ensureCanExchange(
        bytes32 sourceCurrencyKey,
        uint256 sourceAmount,
        bytes32 destinationCurrencyKey
    ) internal view {
        require(sourceCurrencyKey != destinationCurrencyKey, "Can't be same synth");
        require(sourceAmount > 0, "Zero amount");

        bytes32[] memory synthKeys = new bytes32[](2);
        synthKeys[0] = sourceCurrencyKey;
        synthKeys[1] = destinationCurrencyKey;
        require(!exchangeRates().anyRateIsInvalid(synthKeys), "src/dest rate stale or flagged");
    }

    function _ensureCanExchangeAtRound(
        bytes32 sourceCurrencyKey,
        bytes32 destinationCurrencyKey,
        uint256 roundIdForSrc,
        uint256 roundIdForDest
    ) internal view {
        require(sourceCurrencyKey != destinationCurrencyKey, "Can't be same synth");

        bytes32[] memory synthKeys = new bytes32[](2);
        synthKeys[0] = sourceCurrencyKey;
        synthKeys[1] = destinationCurrencyKey;

        uint256[] memory roundIds = new uint256[](2);
        roundIds[0] = roundIdForSrc;
        roundIds[1] = roundIdForDest;
        require(!exchangeRates().anyRateIsInvalidAtRound(synthKeys, roundIds), "src/dest rate stale or flagged");
    }

    function _internalSettle(
        address from,
        bytes32 currencyKey,
        bool updateCache
    )
        internal
        returns (
            uint256 reclaimed,
            uint256 refunded,
            uint256 numEntriesSettled
        )
    {
        require(maxSecsLeftInWaitingPeriod(from, currencyKey) == 0, "Cannot settle during waiting period");

        (
            uint256 reclaimAmount,
            uint256 rebateAmount,
            uint256 entries,
            IExchanger.ExchangeEntrySettlement[] memory settlements
        ) = _settlementOwing(from, currencyKey);

        if (reclaimAmount > rebateAmount) {
            reclaimed = reclaimAmount.sub(rebateAmount);
            reclaim(from, currencyKey, reclaimed);
        } else if (rebateAmount > reclaimAmount) {
            refunded = rebateAmount.sub(reclaimAmount);
            refund(from, currencyKey, refunded);
        }

        // by checking a reclaim or refund we also check that the currency key is still a valid synth,
        // as the deviation check will return 0 if the synth has been removed.
        if (updateCache && (reclaimed > 0 || refunded > 0)) {
            bytes32[] memory key = new bytes32[](1);
            key[0] = currencyKey;
            debtCache().updateCachedSynthDebts(key);
        }

        // emit settlement event for each settled exchange entry
        for (uint256 i = 0; i < settlements.length; i++) {
            emit ExchangeEntrySettled(
                from,
                settlements[i].src,
                settlements[i].amount,
                settlements[i].dest,
                settlements[i].reclaim,
                settlements[i].rebate,
                settlements[i].srcRoundIdAtPeriodEnd,
                settlements[i].destRoundIdAtPeriodEnd,
                settlements[i].timestamp
            );
        }

        numEntriesSettled = entries;

        // Now remove all entries, even if no reclaim and no rebate
        exchangeState().removeEntries(from, currencyKey);
    }

    function reclaim(
        address from,
        bytes32 currencyKey,
        uint256 amount
    ) internal {
        // burn amount from user
        issuer().synths(currencyKey).burn(from, amount);
        ISynthetixInternal(address(synthetix())).emitExchangeReclaim(from, currencyKey, amount);
    }

    function refund(
        address from,
        bytes32 currencyKey,
        uint256 amount
    ) internal {
        // issue amount to user
        issuer().synths(currencyKey).issue(from, amount);
        ISynthetixInternal(address(synthetix())).emitExchangeRebate(from, currencyKey, amount);
    }

    function secsLeftInWaitingPeriodForExchange(uint256 timestamp) internal view returns (uint256) {
        uint256 _waitingPeriodSecs = getWaitingPeriodSecs();
        if (timestamp == 0 || now >= timestamp.add(_waitingPeriodSecs)) {
            return 0;
        }

        return timestamp.add(_waitingPeriodSecs).sub(now);
    }

    /* ========== Exchange Related Fees ========== */
    /// @notice public function to get the total fee rate for a given exchange
    /// @param sourceCurrencyKey The source currency key
    /// @param destinationCurrencyKey The destination currency key
    /// @return The exchange fee rate, and whether the rates are too volatile
    function feeRateForExchange(bytes32 sourceCurrencyKey, bytes32 destinationCurrencyKey) external view returns (uint256) {
        (uint256 feeRate, bool tooVolatile) = _feeRateForExchange(sourceCurrencyKey, destinationCurrencyKey);
        require(!tooVolatile, "too volatile");
        return feeRate;
    }

    /// @notice public function to get the dynamic fee rate for a given exchange
    /// @param sourceCurrencyKey The source currency key
    /// @param destinationCurrencyKey The destination currency key
    /// @return The exchange dynamic fee rate and if rates are too volatile
    function dynamicFeeRateForExchange(bytes32 sourceCurrencyKey, bytes32 destinationCurrencyKey)
        external
        view
        returns (uint256 feeRate, bool tooVolatile)
    {
        return _dynamicFeeRateForExchange(sourceCurrencyKey, destinationCurrencyKey);
    }

    /// @notice Calculate the exchange fee for a given source and destination currency key
    /// @param sourceCurrencyKey The source currency key
    /// @param destinationCurrencyKey The destination currency key
    /// @return The exchange fee rate
    /// @return The exchange dynamic fee rate and if rates are too volatile
    function _feeRateForExchange(bytes32 sourceCurrencyKey, bytes32 destinationCurrencyKey)
        internal
        view
        returns (uint256 feeRate, bool tooVolatile)
    {
        // Get the exchange fee rate as per the source currencyKey and destination currencyKey
        uint256 baseRate = getExchangeFeeRate(sourceCurrencyKey).add(getExchangeFeeRate(destinationCurrencyKey));
        uint256 dynamicFee;
        (dynamicFee, tooVolatile) = _dynamicFeeRateForExchange(sourceCurrencyKey, destinationCurrencyKey);
        return (baseRate.add(dynamicFee), tooVolatile);
    }

    /// @notice Calculate the exchange fee for a given source and destination currency key
    /// @param sourceCurrencyKey The source currency key
    /// @param destinationCurrencyKey The destination currency key
    /// @param roundIdForSrc The round id of the source currency.
    /// @param roundIdForDest The round id of the target currency.
    /// @return The exchange fee rate
    /// @return The exchange dynamic fee rate
    function _feeRateForExchangeAtRounds(
        bytes32 sourceCurrencyKey,
        bytes32 destinationCurrencyKey,
        uint256 roundIdForSrc,
        uint256 roundIdForDest
    ) internal view returns (uint256 feeRate, bool tooVolatile) {
        // Get the exchange fee rate as per the source currencyKey and destination currencyKey
        uint256 baseRate = getExchangeFeeRate(sourceCurrencyKey).add(getExchangeFeeRate(destinationCurrencyKey));
        uint256 dynamicFee;
        (dynamicFee, tooVolatile) = _dynamicFeeRateForExchangeAtRounds(
            sourceCurrencyKey,
            destinationCurrencyKey,
            roundIdForSrc,
            roundIdForDest
        );
        return (baseRate.add(dynamicFee), tooVolatile);
    }

    function _dynamicFeeRateForExchange(bytes32 sourceCurrencyKey, bytes32 destinationCurrencyKey)
        internal
        view
        returns (uint256 dynamicFee, bool tooVolatile)
    {
        DynamicFeeConfig memory config = getExchangeDynamicFeeConfig();
        (uint256 dynamicFeeDst, bool dstVolatile) = _dynamicFeeRateForCurrency(destinationCurrencyKey, config);
        (uint256 dynamicFeeSrc, bool srcVolatile) = _dynamicFeeRateForCurrency(sourceCurrencyKey, config);
        dynamicFee = dynamicFeeDst.add(dynamicFeeSrc);
        // cap to maxFee
        bool overMax = dynamicFee > config.maxFee;
        dynamicFee = overMax ? config.maxFee : dynamicFee;
        return (dynamicFee, overMax || dstVolatile || srcVolatile);
    }

    function _dynamicFeeRateForExchangeAtRounds(
        bytes32 sourceCurrencyKey,
        bytes32 destinationCurrencyKey,
        uint256 roundIdForSrc,
        uint256 roundIdForDest
    ) internal view returns (uint256 dynamicFee, bool tooVolatile) {
        DynamicFeeConfig memory config = getExchangeDynamicFeeConfig();
        (uint256 dynamicFeeDst, bool dstVolatile) = _dynamicFeeRateForCurrencyRound(
            destinationCurrencyKey,
            roundIdForDest,
            config
        );
        (uint256 dynamicFeeSrc, bool srcVolatile) = _dynamicFeeRateForCurrencyRound(sourceCurrencyKey, roundIdForSrc, config);
        dynamicFee = dynamicFeeDst.add(dynamicFeeSrc);
        // cap to maxFee
        bool overMax = dynamicFee > config.maxFee;
        dynamicFee = overMax ? config.maxFee : dynamicFee;
        return (dynamicFee, overMax || dstVolatile || srcVolatile);
    }

    /// @notice Get dynamic dynamicFee for a given currency key (SIP-184)
    /// @param currencyKey The given currency key
    /// @param config dynamic fee calculation configuration params
    /// @return The dynamic fee and if it exceeds max dynamic fee set in config
    function _dynamicFeeRateForCurrency(bytes32 currencyKey, DynamicFeeConfig memory config)
        internal
        view
        returns (uint256 dynamicFee, bool tooVolatile)
    {
        // no dynamic dynamicFee for sUSD or too few rounds
        if (currencyKey == sUSD || config.rounds <= 1) {
            return (0, false);
        }
        uint256 roundId = exchangeRates().getCurrentRoundId(currencyKey);
        return _dynamicFeeRateForCurrencyRound(currencyKey, roundId, config);
    }

    /// @notice Get dynamicFee for a given currency key (SIP-184)
    /// @param currencyKey The given currency key
    /// @param roundId The round id
    /// @param config dynamic fee calculation configuration params
    /// @return The dynamic fee and if it exceeds max dynamic fee set in config
    function _dynamicFeeRateForCurrencyRound(
        bytes32 currencyKey,
        uint256 roundId,
        DynamicFeeConfig memory config
    ) internal view returns (uint256 dynamicFee, bool tooVolatile) {
        // no dynamic dynamicFee for sUSD or too few rounds
        if (currencyKey == sUSD || config.rounds <= 1) {
            return (0, false);
        }
        uint256[] memory prices;
        (prices, ) = exchangeRates().ratesAndUpdatedTimeForCurrencyLastNRounds(currencyKey, config.rounds, roundId);
        dynamicFee = _dynamicFeeCalculation(prices, config.threshold, config.weightDecay);
        // cap to maxFee
        bool overMax = dynamicFee > config.maxFee;
        dynamicFee = overMax ? config.maxFee : dynamicFee;
        return (dynamicFee, overMax);
    }

    /// @notice Calculate dynamic fee according to SIP-184
    /// @param prices A list of prices from the current round to the previous rounds
    /// @param threshold A threshold to clip the price deviation ratop
    /// @param weightDecay A weight decay constant
    /// @return uint dynamic fee rate as decimal
    function _dynamicFeeCalculation(
        uint256[] memory prices,
        uint256 threshold,
        uint256 weightDecay
    ) internal pure returns (uint256) {
        // don't underflow
        if (prices.length == 0) {
            return 0;
        }

        uint256 dynamicFee = 0; // start with 0
        // go backwards in price array
        for (uint256 i = prices.length - 1; i > 0; i--) {
            // apply decay from previous round (will be 0 for first round)
            dynamicFee = dynamicFee.multiplyDecimal(weightDecay);
            // calculate price deviation
            uint256 deviation = _thresholdedAbsDeviationRatio(prices[i - 1], prices[i], threshold);
            // add to total fee
            dynamicFee = dynamicFee.add(deviation);
        }
        return dynamicFee;
    }

    /// absolute price deviation ratio used by dynamic fee calculation
    /// deviationRatio = (abs(current - previous) / previous) - threshold
    /// if negative, zero is returned
    function _thresholdedAbsDeviationRatio(
        uint256 price,
        uint256 previousPrice,
        uint256 threshold
    ) internal pure returns (uint256) {
        if (previousPrice == 0) {
            return 0; // don't divide by zero
        }
        // abs difference between prices
        uint256 absDelta = price > previousPrice ? price - previousPrice : previousPrice - price;
        // relative to previous price
        uint256 deviationRatio = absDelta.divideDecimal(previousPrice);
        // only the positive difference from threshold
        return deviationRatio > threshold ? deviationRatio - threshold : 0;
    }

    function getAmountsForExchange(
        uint256 sourceAmount,
        bytes32 sourceCurrencyKey,
        bytes32 destinationCurrencyKey
    )
        external
        view
        returns (
            uint256 amountReceived,
            uint256 fee,
            uint256 exchangeFeeRate
        )
    {
        // The checks are added for consistency with the checks performed in _exchange()
        // The reverts (instead of no-op returns) are used order to prevent incorrect usage in calling contracts
        // (The no-op in _exchange() is in order to trigger system suspension if needed)

        // check synths active
        systemStatus().requireSynthActive(sourceCurrencyKey);
        systemStatus().requireSynthActive(destinationCurrencyKey);

        // check rates don't deviate above ciruit breaker allowed deviation
        (, bool srcInvalid) = exchangeCircuitBreaker().rateWithInvalid(sourceCurrencyKey);
        (, bool dstInvalid) = exchangeCircuitBreaker().rateWithInvalid(destinationCurrencyKey);
        require(!srcInvalid, "source synth rate invalid");
        require(!dstInvalid, "destination synth rate invalid");

        // check rates not stale or flagged
        _ensureCanExchange(sourceCurrencyKey, sourceAmount, destinationCurrencyKey);

        bool tooVolatile;
        (exchangeFeeRate, tooVolatile) = _feeRateForExchange(sourceCurrencyKey, destinationCurrencyKey);

        // check rates volatility result
        require(!tooVolatile, "exchange rates too volatile");

        (uint256 destinationAmount, , ) = exchangeRates().effectiveValueAndRates(
            sourceCurrencyKey,
            sourceAmount,
            destinationCurrencyKey
        );

        amountReceived = _deductFeesFromAmount(destinationAmount, exchangeFeeRate);
        fee = destinationAmount.sub(amountReceived);
    }

    function _deductFeesFromAmount(uint256 destinationAmount, uint256 exchangeFeeRate)
        internal
        pure
        returns (uint256 amountReceived)
    {
        amountReceived = destinationAmount.multiplyDecimal(SafeDecimalMath.unit().sub(exchangeFeeRate));
    }

    function appendExchange(
        address account,
        bytes32 src,
        uint256 amount,
        bytes32 dest,
        uint256 amountReceived,
        uint256 exchangeFeeRate
    ) internal {
        IExchangeRates exRates = exchangeRates();
        uint256 roundIdForSrc = exRates.getCurrentRoundId(src);
        uint256 roundIdForDest = exRates.getCurrentRoundId(dest);
        exchangeState().appendExchangeEntry(
            account,
            src,
            amount,
            dest,
            amountReceived,
            exchangeFeeRate,
            now,
            roundIdForSrc,
            roundIdForDest
        );

        emit ExchangeEntryAppended(account, src, amount, dest, amountReceived, exchangeFeeRate, roundIdForSrc, roundIdForDest);
    }

    function getRoundIdsAtPeriodEnd(IExchangeState.ExchangeEntry memory exchangeEntry)
        internal
        view
        returns (uint256 srcRoundIdAtPeriodEnd, uint256 destRoundIdAtPeriodEnd)
    {
        IExchangeRates exRates = exchangeRates();
        uint256 _waitingPeriodSecs = getWaitingPeriodSecs();

        srcRoundIdAtPeriodEnd = exRates.getLastRoundIdBeforeElapsedSecs(
            exchangeEntry.src,
            exchangeEntry.roundIdForSrc,
            exchangeEntry.timestamp,
            _waitingPeriodSecs
        );
        destRoundIdAtPeriodEnd = exRates.getLastRoundIdBeforeElapsedSecs(
            exchangeEntry.dest,
            exchangeEntry.roundIdForDest,
            exchangeEntry.timestamp,
            _waitingPeriodSecs
        );
    }

    function _notImplemented() internal pure {
        revert("Cannot be run on this layer");
    }

    // ========== MODIFIERS ==========

    modifier onlySynthetixorSynth() {
        ISynthetix _synthetix = synthetix();
        require(
            msg.sender == address(_synthetix) || _synthetix.synthsByAddress(msg.sender) != bytes32(0),
            "Exchanger: Only synthetix or a synth contract can perform this action"
        );
        _;
    }

    // ========== EVENTS ==========
    event ExchangeEntryAppended(
        address indexed account,
        bytes32 src,
        uint256 amount,
        bytes32 dest,
        uint256 amountReceived,
        uint256 exchangeFeeRate,
        uint256 roundIdForSrc,
        uint256 roundIdForDest
    );

    event ExchangeEntrySettled(
        address indexed from,
        bytes32 src,
        uint256 amount,
        bytes32 dest,
        uint256 reclaim,
        uint256 rebate,
        uint256 srcRoundIdAtPeriodEnd,
        uint256 destRoundIdAtPeriodEnd,
        uint256 exchangeTimestamp
    );
}
