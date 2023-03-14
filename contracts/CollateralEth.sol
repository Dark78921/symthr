pragma solidity ^0.5.16;

pragma experimental ABIEncoderV2;

// Inheritance
import "./Collateral.sol";
// import "openzeppelin-solidity-2.3.0/contracts/utils/ReentrancyGuard.sol";
import "./externals/openzeppelin/ReentrancyGuard.sol";
import "./interfaces/ICollateralEth.sol";

// This contract handles the payable aspects of eth loans.
contract CollateralEth is Collateral, ICollateralEth, ReentrancyGuard {
    mapping(address => uint256) public pendingWithdrawals;

    constructor(
        address _owner,
        ICollateralManager _manager,
        address _resolver,
        bytes32 _collateralKey,
        uint256 _minCratio,
        uint256 _minCollateral
    ) public Collateral(_owner, _manager, _resolver, _collateralKey, _minCratio, _minCollateral) {}

    function open(uint256 amount, bytes32 currency) external payable returns (uint256 id) {
        id = _open(msg.value, amount, currency, false);
    }

    function close(uint256 id) external returns (uint256 amount, uint256 collateral) {
        (amount, collateral) = _close(msg.sender, id);

        pendingWithdrawals[msg.sender] = pendingWithdrawals[msg.sender].add(collateral);
    }

    function deposit(address borrower, uint256 id) external payable returns (uint256 principal, uint256 collateral) {
        (principal, collateral) = _deposit(borrower, id, msg.value);
    }

    function withdraw(uint256 id, uint256 amount) external returns (uint256 principal, uint256 collateral) {
        (principal, collateral) = _withdraw(id, amount);

        pendingWithdrawals[msg.sender] = pendingWithdrawals[msg.sender].add(amount);
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

        pendingWithdrawals[msg.sender] = pendingWithdrawals[msg.sender].add(collateralLiquidated);
    }

    function claim(uint256 amount) external nonReentrant {
        // If they try to withdraw more than their total balance, it will fail on the safe sub.
        pendingWithdrawals[msg.sender] = pendingWithdrawals[msg.sender].sub(amount);

        // solhint-disable avoid-low-level-calls
        (bool success, ) = msg.sender.call.value(amount)("");
        require(success, "Transfer failed");
    }
}
