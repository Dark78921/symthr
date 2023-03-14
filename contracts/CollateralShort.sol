pragma solidity ^0.5.16;

pragma experimental ABIEncoderV2;

// Inheritance
import "./Collateral.sol";

contract CollateralShort is Collateral {
    constructor(
        address _owner,
        ICollateralManager _manager,
        address _resolver,
        bytes32 _collateralKey,
        uint256 _minCratio,
        uint256 _minCollateral
    ) public Collateral(_owner, _manager, _resolver, _collateralKey, _minCratio, _minCollateral) {}

    function open(
        uint256 collateral,
        uint256 amount,
        bytes32 currency
    ) external returns (uint256 id) {
        // Transfer from will throw if they didn't set the allowance
        IERC20(address(_synthsUSD())).transferFrom(msg.sender, address(this), collateral);

        id = _open(collateral, amount, currency, true);
    }

    function close(uint256 id) external returns (uint256 amount, uint256 collateral) {
        (amount, collateral) = _close(msg.sender, id);

        IERC20(address(_synthsUSD())).transfer(msg.sender, collateral);
    }

    function deposit(
        address borrower,
        uint256 id,
        uint256 amount
    ) external returns (uint256 principal, uint256 collateral) {
        require(amount <= IERC20(address(_synthsUSD())).allowance(msg.sender, address(this)), "Allowance too low");

        IERC20(address(_synthsUSD())).transferFrom(msg.sender, address(this), amount);

        (principal, collateral) = _deposit(borrower, id, amount);
    }

    function withdraw(uint256 id, uint256 amount) external returns (uint256 principal, uint256 collateral) {
        (principal, collateral) = _withdraw(id, amount);

        IERC20(address(_synthsUSD())).transfer(msg.sender, amount);
    }

    function repay(
        address borrower,
        uint256 id,
        uint256 amount
    ) external returns (uint256 principal, uint256 collateral) {
        (principal, collateral) = _repay(borrower, msg.sender, id, amount);
    }

    function closeWithCollateral(uint256 id) external returns (uint256 amount, uint256 collateral) {
        (amount, collateral) = _closeWithCollateral(msg.sender, id);

        if (collateral > 0) {
            IERC20(address(_synthsUSD())).transfer(msg.sender, collateral);
        }
    }

    function repayWithCollateral(uint256 id, uint256 amount) external returns (uint256 principal, uint256 collateral) {
        (principal, collateral) = _repayWithCollateral(msg.sender, id, amount);
    }

    // Needed for Lyra.
    function getShortAndCollateral(
        address, /* borrower */
        uint256 id
    ) external view returns (uint256 principal, uint256 collateral) {
        Loan memory loan = loans[id];
        return (loan.amount, loan.collateral);
    }

    function draw(uint256 id, uint256 amount) external returns (uint256 principal, uint256 collateral) {
        (principal, collateral) = _draw(id, amount);
    }

    function liquidate(
        address borrower,
        uint256 id,
        uint256 amount
    ) external {
        uint256 collateralLiquidated = _liquidate(borrower, id, amount);

        IERC20(address(_synthsUSD())).transfer(msg.sender, collateralLiquidated);
    }

    function _repayWithCollateral(
        address borrower,
        uint256 id,
        uint256 payment
    ) internal rateIsValid issuanceIsActive returns (uint256 amount, uint256 collateral) {
        // 0. Get the loan to repay and accrue interest.
        Loan storage loan = _getLoanAndAccrueInterest(id, borrower);

        // 1. Check loan is open and last interaction time.
        _checkLoanAvailable(loan);

        // 2. Use the payment to cover accrued interest and reduce debt.
        // The returned amounts are the interests paid and the principal component used to reduce debt only.
        require(payment <= loan.amount.add(loan.accruedInterest), "Payment too high");
        _processPayment(loan, payment);

        // 3. Get the equivalent payment amount in sUSD, and also distinguish
        // the fee that would be charged for both principal and interest.
        (uint256 expectedAmount, uint256 exchangeFee, ) = _exchanger().getAmountsForExchange(payment, loan.currency, sUSD);
        uint256 paymentSUSD = expectedAmount.add(exchangeFee);

        // 4. Reduce the collateral by the equivalent (total) payment amount in sUSD,
        // but add the fee instead of deducting it.
        uint256 collateralToRemove = paymentSUSD.add(exchangeFee);
        loan.collateral = loan.collateral.sub(collateralToRemove);

        // 5. Pay exchange fees.
        _payFees(exchangeFee, sUSD);

        // 6. Burn sUSD held in the contract.
        _synthsUSD().burn(address(this), collateralToRemove);

        // 7. Update the last interaction time.
        loan.lastInteraction = block.timestamp;

        // 8. Emit the event for the collateral repayment.
        emit LoanRepaymentMade(borrower, borrower, id, payment, loan.amount);

        // 9. Return the amount repaid and the remaining collateral.
        return (payment, loan.collateral);
    }

    function _closeWithCollateral(address borrower, uint256 id) internal returns (uint256 amount, uint256 collateral) {
        // 0. Get the loan to repay and accrue interest.
        Loan storage loan = _getLoanAndAccrueInterest(id, borrower);

        // 1. Repay the loan with its collateral.
        uint256 amountToRepay = loan.amount.add(loan.accruedInterest);
        (amount, collateral) = _repayWithCollateral(borrower, id, amountToRepay);

        // 2. Record loan as closed.
        _recordLoanAsClosed(loan);

        // 3. Emit the event for the loan closed by repayment.
        emit LoanClosedByRepayment(borrower, id, amount, collateral);

        // 4. Explicitely return the values.
        return (amount, collateral);
    }
}
