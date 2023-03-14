pragma solidity >=0.4.24;

interface ILiquidator {
    // Views
    function issuanceRatio() external view returns (uint256);

    function liquidationDelay() external view returns (uint256);

    function liquidationRatio() external view returns (uint256);

    function liquidationEscrowDuration() external view returns (uint256);

    function liquidationPenalty() external view returns (uint256);

    function selfLiquidationPenalty() external view returns (uint256);

    function liquidateReward() external view returns (uint256);

    function flagReward() external view returns (uint256);

    function liquidationCollateralRatio() external view returns (uint256);

    function getLiquidationDeadlineForAccount(address account) external view returns (uint256);

    function getLiquidationCallerForAccount(address account) external view returns (address);

    function isLiquidationOpen(address account, bool isSelfLiquidation) external view returns (bool);

    function isLiquidationDeadlinePassed(address account) external view returns (bool);

    function calculateAmountToFixCollateral(
        uint256 debtBalance,
        uint256 collateral,
        uint256 penalty
    ) external view returns (uint256);

    // Mutative Functions
    function flagAccountForLiquidation(address account) external;

    // Restricted: used internally to Synthetix contracts
    function removeAccountInLiquidation(address account) external;

    function checkAndRemoveAccountInLiquidation(address account) external;
}
