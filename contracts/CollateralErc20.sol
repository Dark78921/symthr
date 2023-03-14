pragma solidity ^0.5.16;

pragma experimental ABIEncoderV2;

// Inheritance
import "./Collateral.sol";
import "./interfaces/ICollateralErc20.sol";

// This contract handles the specific ERC20 implementation details of managing a loan.
contract CollateralErc20 is ICollateralErc20, Collateral {
    // The underlying asset for this ERC20 collateral
    address public underlyingContract;

    uint256 public underlyingContractDecimals;

    constructor(
        address _owner,
        ICollateralManager _manager,
        address _resolver,
        bytes32 _collateralKey,
        uint256 _minCratio,
        uint256 _minCollateral,
        address _underlyingContract,
        uint256 _underlyingDecimals
    ) public Collateral(_owner, _manager, _resolver, _collateralKey, _minCratio, _minCollateral) {
        underlyingContract = _underlyingContract;

        underlyingContractDecimals = _underlyingDecimals;
    }

    function open(
        uint256 collateral,
        uint256 amount,
        bytes32 currency
    ) external returns (uint256 id) {
        require(collateral <= IERC20(underlyingContract).allowance(msg.sender, address(this)), "Allowance not high enough");

        // only transfer the actual collateral
        IERC20(underlyingContract).safeTransferFrom(msg.sender, address(this), collateral);

        // scale up before entering the system.
        uint256 scaledCollateral = scaleUpCollateral(collateral);

        id = _open(scaledCollateral, amount, currency, false);
    }

    function close(uint256 id) external returns (uint256 amount, uint256 collateral) {
        (amount, collateral) = _close(msg.sender, id);

        // scale down before transferring back.
        uint256 scaledCollateral = scaleDownCollateral(collateral);

        IERC20(underlyingContract).safeTransfer(msg.sender, scaledCollateral);
    }

    function deposit(
        address borrower,
        uint256 id,
        uint256 amount
    ) external returns (uint256 principal, uint256 collateral) {
        require(amount <= IERC20(underlyingContract).allowance(msg.sender, address(this)), "Allowance not high enough");

        IERC20(underlyingContract).safeTransferFrom(msg.sender, address(this), amount);

        // scale up before entering the system.
        uint256 scaledAmount = scaleUpCollateral(amount);

        (principal, collateral) = _deposit(borrower, id, scaledAmount);
    }

    function withdraw(uint256 id, uint256 amount) external returns (uint256 principal, uint256 collateral) {
        // scale up before entering the system.
        uint256 scaledAmount = scaleUpCollateral(amount);

        (principal, collateral) = _withdraw(id, scaledAmount);

        // scale down before transferring back.
        uint256 scaledWithdraw = scaleDownCollateral(collateral);

        IERC20(underlyingContract).safeTransfer(msg.sender, scaledWithdraw);
    }

    function repay(
        address borrower,
        uint256 id,
        uint256 amount
    ) external returns (uint256 principal, uint256 collateral) {
        (principal, collateral) = _repay(borrower, msg.sender, id, amount);
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

        // scale down before transferring back.
        uint256 scaledCollateral = scaleDownCollateral(collateralLiquidated);

        IERC20(underlyingContract).safeTransfer(msg.sender, scaledCollateral);
    }

    function scaleUpCollateral(uint256 collateral) public view returns (uint256 scaledUp) {
        uint256 conversionFactor = 10**uint256(SafeMath.sub(18, underlyingContractDecimals));

        scaledUp = uint256(uint256(collateral).mul(conversionFactor));
    }

    function scaleDownCollateral(uint256 collateral) public view returns (uint256 scaledDown) {
        uint256 conversionFactor = 10**uint256(SafeMath.sub(18, underlyingContractDecimals));

        scaledDown = collateral.div(conversionFactor);
    }
}
