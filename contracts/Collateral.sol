pragma solidity ^0.5.16;

pragma experimental ABIEncoderV2;

// import "openzeppelin-solidity-2.3.0/contracts/token/ERC20/SafeERC20.sol";
import "./externals/openzeppelin/SafeERC20.sol";

// Inheritance
import "./Owned.sol";
import "./MixinSystemSettings.sol";
import "./interfaces/ICollateralLoan.sol";

// Libraries
import "./SafeDecimalMath.sol";

// Internal references
import "./interfaces/ICollateralUtil.sol";
import "./interfaces/ICollateralManager.sol";
import "./interfaces/ISystemStatus.sol";
import "./interfaces/IFeePool.sol";
import "./interfaces/IIssuer.sol";
import "./interfaces/ISynth.sol";
import "./interfaces/IExchangeRates.sol";
import "./interfaces/IExchanger.sol";
import "./interfaces/IShortingRewards.sol";

contract Collateral is ICollateralLoan, Owned, MixinSystemSettings {
    /* ========== LIBRARIES ========== */
    using SafeMath for uint256;
    using SafeDecimalMath for uint256;
    using SafeERC20 for IERC20;

    /* ========== CONSTANTS ========== */

    bytes32 internal constant sUSD = "sUSD";

    // ========== STATE VARIABLES ==========

    // The synth corresponding to the collateral.
    bytes32 public collateralKey;

    // Stores open loans.
    mapping(uint256 => Loan) public loans;

    ICollateralManager public manager;

    // The synths that this contract can issue.
    bytes32[] public synths;

    // Map from currency key to synth contract name.
    mapping(bytes32 => bytes32) public synthsByKey;

    // Map from currency key to the shorting rewards contract
    mapping(bytes32 => address) public shortingRewards;

    // ========== SETTER STATE VARIABLES ==========

    // The minimum collateral ratio required to avoid liquidation.
    uint256 public minCratio;

    // The minimum amount of collateral to create a loan.
    uint256 public minCollateral;

    // The fee charged for issuing a loan.
    uint256 public issueFeeRate;

    bool public canOpenLoans = true;

    /* ========== ADDRESS RESOLVER CONFIGURATION ========== */

    bytes32 private constant CONTRACT_SYSTEMSTATUS = "SystemStatus";
    bytes32 private constant CONTRACT_EXRATES = "ExchangeRates";
    bytes32 private constant CONTRACT_EXCHANGER = "Exchanger";
    bytes32 private constant CONTRACT_FEEPOOL = "FeePool";
    bytes32 private constant CONTRACT_SYNTHSUSD = "SynthsUSD";
    bytes32 private constant CONTRACT_COLLATERALUTIL = "CollateralUtil";

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _owner,
        ICollateralManager _manager,
        address _resolver,
        bytes32 _collateralKey,
        uint256 _minCratio,
        uint256 _minCollateral
    ) public Owned(_owner) MixinSystemSettings(_resolver) {
        manager = _manager;
        collateralKey = _collateralKey;
        minCratio = _minCratio;
        minCollateral = _minCollateral;
    }

    /* ========== VIEWS ========== */

    function resolverAddressesRequired() public view returns (bytes32[] memory addresses) {
        bytes32[] memory existingAddresses = MixinSystemSettings.resolverAddressesRequired();
        bytes32[] memory newAddresses = new bytes32[](6);
        newAddresses[0] = CONTRACT_FEEPOOL;
        newAddresses[1] = CONTRACT_EXRATES;
        newAddresses[2] = CONTRACT_EXCHANGER;
        newAddresses[3] = CONTRACT_SYSTEMSTATUS;
        newAddresses[4] = CONTRACT_SYNTHSUSD;
        newAddresses[5] = CONTRACT_COLLATERALUTIL;

        bytes32[] memory combined = combineArrays(existingAddresses, newAddresses);

        addresses = combineArrays(combined, synths);
    }

    /* ---------- Related Contracts ---------- */

    function _systemStatus() internal view returns (ISystemStatus) {
        return ISystemStatus(requireAndGetAddress(CONTRACT_SYSTEMSTATUS));
    }

    function _synth(bytes32 synthName) internal view returns (ISynth) {
        return ISynth(requireAndGetAddress(synthName));
    }

    function _synthsUSD() internal view returns (ISynth) {
        return ISynth(requireAndGetAddress(CONTRACT_SYNTHSUSD));
    }

    function _exchangeRates() internal view returns (IExchangeRates) {
        return IExchangeRates(requireAndGetAddress(CONTRACT_EXRATES));
    }

    function _exchanger() internal view returns (IExchanger) {
        return IExchanger(requireAndGetAddress(CONTRACT_EXCHANGER));
    }

    function _feePool() internal view returns (IFeePool) {
        return IFeePool(requireAndGetAddress(CONTRACT_FEEPOOL));
    }

    function _collateralUtil() internal view returns (ICollateralUtil) {
        return ICollateralUtil(requireAndGetAddress(CONTRACT_COLLATERALUTIL));
    }

    /* ---------- Public Views ---------- */

    function collateralRatio(uint256 id) public view returns (uint256 cratio) {
        Loan memory loan = loans[id];
        return _collateralUtil().getCollateralRatio(loan, collateralKey);
    }

    function liquidationAmount(uint256 id) public view returns (uint256 liqAmount) {
        Loan memory loan = loans[id];
        return _collateralUtil().liquidationAmount(loan, minCratio, collateralKey);
    }

    // The maximum number of synths issuable for this amount of collateral
    function maxLoan(uint256 amount, bytes32 currency) public view returns (uint256 max) {
        return _collateralUtil().maxLoan(amount, currency, minCratio, collateralKey);
    }

    function areSynthsAndCurrenciesSet(bytes32[] calldata _synthNamesInResolver, bytes32[] calldata _synthKeys)
        external
        view
        returns (bool)
    {
        if (synths.length != _synthNamesInResolver.length) {
            return false;
        }

        for (uint256 i = 0; i < _synthNamesInResolver.length; i++) {
            bytes32 synthName = _synthNamesInResolver[i];
            if (synths[i] != synthName) {
                return false;
            }
            if (synthsByKey[_synthKeys[i]] != synths[i]) {
                return false;
            }
        }

        return true;
    }

    /* ---------- SETTERS ---------- */

    function setMinCollateral(uint256 _minCollateral) external onlyOwner {
        minCollateral = _minCollateral;
        emit MinCollateralUpdated(minCollateral);
    }

    function setIssueFeeRate(uint256 _issueFeeRate) external onlyOwner {
        issueFeeRate = _issueFeeRate;
        emit IssueFeeRateUpdated(issueFeeRate);
    }

    function setCanOpenLoans(bool _canOpenLoans) external onlyOwner {
        canOpenLoans = _canOpenLoans;
        emit CanOpenLoansUpdated(canOpenLoans);
    }

    /* ---------- UTILITIES ---------- */

    // Check the account has enough of the synth to make the payment
    function _checkSynthBalance(
        address payer,
        bytes32 key,
        uint256 amount
    ) internal view {
        require(IERC20(address(_synth(synthsByKey[key]))).balanceOf(payer) >= amount, "Not enough balance");
    }

    // We set the interest index to 0 to indicate the loan has been closed.
    function _checkLoanAvailable(Loan memory loan) internal view {
        _isLoanOpen(loan.interestIndex);
        require(loan.lastInteraction.add(getInteractionDelay(address(this))) <= block.timestamp, "Recently interacted");
    }

    function _isLoanOpen(uint256 interestIndex) internal pure {
        require(interestIndex != 0, "Loan is closed");
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /* ---------- Synths ---------- */

    function addSynths(bytes32[] calldata _synthNamesInResolver, bytes32[] calldata _synthKeys) external onlyOwner {
        require(_synthNamesInResolver.length == _synthKeys.length, "Array length mismatch");

        for (uint256 i = 0; i < _synthNamesInResolver.length; i++) {
            bytes32 synthName = _synthNamesInResolver[i];
            synths.push(synthName);
            synthsByKey[_synthKeys[i]] = synthName;
        }

        // ensure cache has the latest
        rebuildCache();
    }

    /* ---------- Rewards Contracts ---------- */

    function addRewardsContracts(address rewardsContract, bytes32 synth) external onlyOwner {
        shortingRewards[synth] = rewardsContract;
    }

    /* ---------- LOAN INTERACTIONS ---------- */

    function _open(
        uint256 collateral,
        uint256 amount,
        bytes32 currency,
        bool short
    ) internal rateIsValid issuanceIsActive returns (uint256 id) {
        // 0. Check if able to open loans.
        require(canOpenLoans, "Open disabled");

        // 1. We can only issue certain synths.
        require(synthsByKey[currency] > 0, "Not allowed to issue");

        // 2. Make sure the synth rate is not invalid.
        require(!_exchangeRates().rateIsInvalid(currency), "Invalid rate");

        // 3. Collateral >= minimum collateral size.
        require(collateral >= minCollateral, "Not enough collateral");

        // 4. Check we haven't hit the debt cap for non snx collateral.
        (bool canIssue, bool anyRateIsInvalid) = manager.exceedsDebtLimit(amount, currency);

        // 5. Check if we've hit the debt cap or any rate is invalid.
        require(canIssue && !anyRateIsInvalid, "Debt limit or invalid rate");

        // 6. Require requested loan < max loan.
        require(amount <= maxLoan(collateral, currency), "Exceed max borrow power");

        // 7. This fee is denominated in the currency of the loan.
        uint256 issueFee = amount.multiplyDecimalRound(issueFeeRate);

        // 8. Calculate the minting fee and subtract it from the loan amount.
        uint256 loanAmountMinusFee = amount.sub(issueFee);

        // 9. Get a Loan ID.
        id = manager.getNewLoanId();

        // 10. Create the loan struct.
        loans[id] = Loan({
            id: id,
            account: msg.sender,
            collateral: collateral,
            currency: currency,
            amount: amount,
            short: short,
            accruedInterest: 0,
            interestIndex: 0,
            lastInteraction: block.timestamp
        });

        // 11. Accrue interest on the loan.
        _accrueInterest(loans[id]);

        // 12. Pay the minting fees to the fee pool.
        _payFees(issueFee, currency);

        // 13. If its short, convert back to sUSD, otherwise issue the loan.
        if (short) {
            _synthsUSD().issue(msg.sender, _exchangeRates().effectiveValue(currency, loanAmountMinusFee, sUSD));
            manager.incrementShorts(currency, amount);

            if (shortingRewards[currency] != address(0)) {
                IShortingRewards(shortingRewards[currency]).enrol(msg.sender, amount);
            }
        } else {
            _synth(synthsByKey[currency]).issue(msg.sender, loanAmountMinusFee);
            manager.incrementLongs(currency, amount);
        }

        // 14. Emit event for the newly opened loan.
        emit LoanCreated(msg.sender, id, amount, collateral, currency, issueFee);
    }

    function _close(address borrower, uint256 id)
        internal
        rateIsValid
        issuanceIsActive
        returns (uint256 amount, uint256 collateral)
    {
        // 0. Get the loan and accrue interest.
        Loan storage loan = _getLoanAndAccrueInterest(id, borrower);

        // 1. Check loan is open and last interaction time.
        _checkLoanAvailable(loan);

        // 2. Record loan as closed.
        (amount, collateral) = _closeLoan(borrower, borrower, loan);

        // 3. Emit the event for the closed loan.
        emit LoanClosed(borrower, id);
    }

    function _closeByLiquidation(
        address borrower,
        address liquidator,
        Loan storage loan
    ) internal returns (uint256 amount, uint256 collateral) {
        (amount, collateral) = _closeLoan(borrower, liquidator, loan);

        // Emit the event for the loan closed by liquidation.
        emit LoanClosedByLiquidation(borrower, loan.id, liquidator, amount, collateral);
    }

    function _closeLoan(
        address borrower,
        address liquidator,
        Loan storage loan
    ) internal returns (uint256 amount, uint256 collateral) {
        // 0. Work out the total amount owing on the loan.
        uint256 total = loan.amount.add(loan.accruedInterest);

        // 1. Store this for the event.
        amount = loan.amount;

        // 2. Return collateral to the child class so it knows how much to transfer.
        collateral = loan.collateral;

        // 3. Check that the liquidator has enough synths.
        _checkSynthBalance(liquidator, loan.currency, total);

        // 4. Burn the synths.
        _synth(synthsByKey[loan.currency]).burn(liquidator, total);

        // 5. Tell the manager.
        if (loan.short) {
            manager.decrementShorts(loan.currency, loan.amount);

            if (shortingRewards[loan.currency] != address(0)) {
                IShortingRewards(shortingRewards[loan.currency]).withdraw(borrower, loan.amount);
            }
        } else {
            manager.decrementLongs(loan.currency, loan.amount);
        }

        // 6. Pay fees.
        _payFees(loan.accruedInterest, loan.currency);

        // 7. Record loan as closed.
        _recordLoanAsClosed(loan);
    }

    function _deposit(
        address account,
        uint256 id,
        uint256 amount
    ) internal rateIsValid issuanceIsActive returns (uint256, uint256) {
        // 0. They sent some value > 0
        require(amount > 0, "Deposit must be above 0");

        // 1. Get the loan.
        // Owner is not important here, as it is a donation to the collateral of the loan
        Loan storage loan = loans[id];

        // 2. Check loan hasn't been closed or liquidated.
        _isLoanOpen(loan.interestIndex);

        // 3. Accrue interest on the loan.
        _accrueInterest(loan);

        // 4. Add the collateral.
        loan.collateral = loan.collateral.add(amount);

        // 5. Emit the event for the deposited collateral.
        emit CollateralDeposited(account, id, amount, loan.collateral);

        return (loan.amount, loan.collateral);
    }

    function _withdraw(uint256 id, uint256 amount) internal rateIsValid issuanceIsActive returns (uint256, uint256) {
        // 0. Get the loan and accrue interest.
        Loan storage loan = _getLoanAndAccrueInterest(id, msg.sender);

        // 1. Subtract the collateral.
        loan.collateral = loan.collateral.sub(amount);

        // 2. Check that the new amount does not put them under the minimum c ratio.
        _checkLoanRatio(loan);

        // 3. Emit the event for the withdrawn collateral.
        emit CollateralWithdrawn(msg.sender, id, amount, loan.collateral);

        return (loan.amount, loan.collateral);
    }

    function _liquidate(
        address borrower,
        uint256 id,
        uint256 payment
    ) internal rateIsValid issuanceIsActive returns (uint256 collateralLiquidated) {
        require(payment > 0, "Payment must be above 0");

        // 0. Get the loan and accrue interest.
        Loan storage loan = _getLoanAndAccrueInterest(id, borrower);

        // 1. Check they have enough balance to make the payment.
        _checkSynthBalance(msg.sender, loan.currency, payment);

        // 2. Check they are eligible for liquidation.
        // Note: this will revert if collateral is 0, however that should only be possible if the loan amount is 0.
        require(_collateralUtil().getCollateralRatio(loan, collateralKey) < minCratio, "Cratio above liq ratio");

        // 3. Determine how much needs to be liquidated to fix their c ratio.
        uint256 liqAmount = _collateralUtil().liquidationAmount(loan, minCratio, collateralKey);

        // 4. Only allow them to liquidate enough to fix the c ratio.
        uint256 amountToLiquidate = liqAmount < payment ? liqAmount : payment;

        // 5. Work out the total amount owing on the loan.
        uint256 amountOwing = loan.amount.add(loan.accruedInterest);

        // 6. If its greater than the amount owing, we need to close the loan.
        if (amountToLiquidate >= amountOwing) {
            (, collateralLiquidated) = _closeByLiquidation(borrower, msg.sender, loan);
            return collateralLiquidated;
        }

        // 7. Check they have enough balance to liquidate the loan.
        _checkSynthBalance(msg.sender, loan.currency, amountToLiquidate);

        // 8. Process the payment to workout interest/principal split.
        _processPayment(loan, amountToLiquidate);

        // 9. Work out how much collateral to redeem.
        collateralLiquidated = _collateralUtil().collateralRedeemed(loan.currency, amountToLiquidate, collateralKey);
        loan.collateral = loan.collateral.sub(collateralLiquidated);

        // 10. Burn the synths from the liquidator.
        _synth(synthsByKey[loan.currency]).burn(msg.sender, amountToLiquidate);

        // 11. Emit the event for the partial liquidation.
        emit LoanPartiallyLiquidated(borrower, id, msg.sender, amountToLiquidate, collateralLiquidated);
    }

    function _repay(
        address borrower,
        address repayer,
        uint256 id,
        uint256 payment
    ) internal rateIsValid issuanceIsActive returns (uint256, uint256) {
        // 0. Get the loan.
        // Owner is not important here, as it is a donation to repay the loan.
        Loan storage loan = loans[id];

        // 1. Check loan is open and last interaction time.
        _checkLoanAvailable(loan);

        // 2. Check the spender has enough synths to make the repayment
        _checkSynthBalance(repayer, loan.currency, payment);

        // 3. Accrue interest on the loan.
        _accrueInterest(loan);

        // 4. Process the payment.
        _processPayment(loan, payment);

        // 5. Burn synths from the payer
        _synth(synthsByKey[loan.currency]).burn(repayer, payment);

        // 6. Update the last interaction time.
        loan.lastInteraction = block.timestamp;

        // 7. Emit the event the repayment.
        emit LoanRepaymentMade(borrower, repayer, id, payment, loan.amount);

        // 8. Return the loan amount and collateral after repaying.
        return (loan.amount, loan.collateral);
    }

    function _draw(uint256 id, uint256 amount) internal rateIsValid issuanceIsActive returns (uint256, uint256) {
        // 0. Get the loan and accrue interest.
        Loan storage loan = _getLoanAndAccrueInterest(id, msg.sender);

        // 1. Check last interaction time.
        _checkLoanAvailable(loan);

        // 2. Add the requested amount.
        loan.amount = loan.amount.add(amount);

        // 3. If it is below the minimum, don't allow this draw.
        _checkLoanRatio(loan);

        // 4. This fee is denominated in the currency of the loan
        uint256 issueFee = amount.multiplyDecimalRound(issueFeeRate);

        // 5. Calculate the minting fee and subtract it from the draw amount
        uint256 amountMinusFee = amount.sub(issueFee);

        // 6. If its short, issue the synths.
        if (loan.short) {
            manager.incrementShorts(loan.currency, amount);
            _synthsUSD().issue(msg.sender, _exchangeRates().effectiveValue(loan.currency, amountMinusFee, sUSD));

            if (shortingRewards[loan.currency] != address(0)) {
                IShortingRewards(shortingRewards[loan.currency]).enrol(msg.sender, amount);
            }
        } else {
            manager.incrementLongs(loan.currency, amount);
            _synth(synthsByKey[loan.currency]).issue(msg.sender, amountMinusFee);
        }

        // 7. Pay the minting fees to the fee pool
        _payFees(issueFee, loan.currency);

        // 8. Update the last interaction time.
        loan.lastInteraction = block.timestamp;

        // 9. Emit the event for the draw down.
        emit LoanDrawnDown(msg.sender, id, amount);

        return (loan.amount, loan.collateral);
    }

    // Update the cumulative interest rate for the currency that was interacted with.
    function _accrueInterest(Loan storage loan) internal {
        (uint256 differential, uint256 newIndex) = manager.accrueInterest(loan.interestIndex, loan.currency, loan.short);

        // If the loan was just opened, don't record any interest. Otherwise multiply by the amount outstanding.
        uint256 interest = loan.interestIndex == 0 ? 0 : loan.amount.multiplyDecimal(differential);

        // Update the loan.
        loan.accruedInterest = loan.accruedInterest.add(interest);
        loan.interestIndex = newIndex;
    }

    // Works out the amount of interest and principal after a repayment is made.
    function _processPayment(Loan storage loan, uint256 payment) internal {
        require(payment > 0, "Payment must be above 0");

        if (loan.accruedInterest > 0) {
            uint256 interestPaid = payment > loan.accruedInterest ? loan.accruedInterest : payment;
            loan.accruedInterest = loan.accruedInterest.sub(interestPaid);
            payment = payment.sub(interestPaid);

            _payFees(interestPaid, loan.currency);
        }

        // If there is more payment left after the interest, pay down the principal.
        if (payment > 0) {
            loan.amount = loan.amount.sub(payment);

            // And get the manager to reduce the total long/short balance.
            if (loan.short) {
                manager.decrementShorts(loan.currency, payment);

                if (shortingRewards[loan.currency] != address(0)) {
                    IShortingRewards(shortingRewards[loan.currency]).withdraw(loan.account, payment);
                }
            } else {
                manager.decrementLongs(loan.currency, payment);
            }
        }
    }

    // Take an amount of fees in a certain synth and convert it to sUSD before paying the fee pool.
    function _payFees(uint256 amount, bytes32 synth) internal {
        if (amount > 0) {
            if (synth != sUSD) {
                amount = _exchangeRates().effectiveValue(synth, amount, sUSD);
            }
            _synthsUSD().issue(_feePool().FEE_ADDRESS(), amount);
            _feePool().recordFeePaid(amount);
        }
    }

    function _recordLoanAsClosed(Loan storage loan) internal {
        loan.amount = 0;
        loan.collateral = 0;
        loan.accruedInterest = 0;
        loan.interestIndex = 0;
        loan.lastInteraction = block.timestamp;
    }

    function _getLoanAndAccrueInterest(uint256 id, address owner) internal returns (Loan storage loan) {
        loan = loans[id];

        // Make sure the loan is open and it is the borrower.
        _isLoanOpen(loan.interestIndex);

        require(loan.account == owner, "Must be borrower");

        _accrueInterest(loan);
    }

    function _checkLoanRatio(Loan storage loan) internal view {
        if (loan.amount == 0) {
            return;
        }
        require(collateralRatio(loan.id) > minCratio, "Cratio too low");
    }

    // ========== MODIFIERS ==========

    modifier rateIsValid() {
        _requireRateIsValid();
        _;
    }

    function _requireRateIsValid() private view {
        require(!_exchangeRates().rateIsInvalid(collateralKey), "Invalid rate");
    }

    modifier issuanceIsActive() {
        _requireIssuanceIsActive();
        _;
    }

    function _requireIssuanceIsActive() private view {
        _systemStatus().requireIssuanceActive();
    }

    // ========== EVENTS ==========

    // Setters
    event MinCollateralUpdated(uint256 minCollateral);
    event IssueFeeRateUpdated(uint256 issueFeeRate);
    event CanOpenLoansUpdated(bool canOpenLoans);

    // Loans
    event LoanCreated(
        address indexed account,
        uint256 id,
        uint256 amount,
        uint256 collateral,
        bytes32 currency,
        uint256 issuanceFee
    );
    event LoanClosed(address indexed account, uint256 id);
    event CollateralDeposited(address indexed account, uint256 id, uint256 amountDeposited, uint256 collateralAfter);
    event CollateralWithdrawn(address indexed account, uint256 id, uint256 amountWithdrawn, uint256 collateralAfter);
    event LoanRepaymentMade(
        address indexed account,
        address indexed repayer,
        uint256 id,
        uint256 amountRepaid,
        uint256 amountAfter
    );
    event LoanDrawnDown(address indexed account, uint256 id, uint256 amount);
    event LoanPartiallyLiquidated(
        address indexed account,
        uint256 id,
        address liquidator,
        uint256 amountLiquidated,
        uint256 collateralLiquidated
    );
    event LoanClosedByLiquidation(
        address indexed account,
        uint256 id,
        address indexed liquidator,
        uint256 amountLiquidated,
        uint256 collateralLiquidated
    );
    event LoanClosedByRepayment(address indexed account, uint256 id, uint256 amountRepaid, uint256 collateralAfter);
}
