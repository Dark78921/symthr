pragma solidity >=0.4.24;

pragma experimental ABIEncoderV2;

import "./ICollateralLoan.sol";

interface ICollateralUtil {
    function getCollateralRatio(ICollateralLoan.Loan calldata loan, bytes32 collateralKey) external view returns (uint256 cratio);

    function maxLoan(
        uint256 amount,
        bytes32 currency,
        uint256 minCratio,
        bytes32 collateralKey
    ) external view returns (uint256 max);

    function liquidationAmount(
        ICollateralLoan.Loan calldata loan,
        uint256 minCratio,
        bytes32 collateralKey
    ) external view returns (uint256 amount);

    function collateralRedeemed(
        bytes32 currency,
        uint256 amount,
        bytes32 collateralKey
    ) external view returns (uint256 collateral);
}
