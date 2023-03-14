pragma solidity >=0.4.24;

// https://docs.synthetix.io/contracts/source/interfaces/isystemsettings
interface ISystemSettings {
    // Views
    function waitingPeriodSecs() external view returns (uint256);

    function priceDeviationThresholdFactor() external view returns (uint256);

    function issuanceRatio() external view returns (uint256);

    function feePeriodDuration() external view returns (uint256);

    function targetThreshold() external view returns (uint256);

    function liquidationDelay() external view returns (uint256);

    function liquidationRatio() external view returns (uint256);

    function liquidationEscrowDuration() external view returns (uint256);

    function liquidationPenalty() external view returns (uint256);

    function snxLiquidationPenalty() external view returns (uint256);

    function selfLiquidationPenalty() external view returns (uint256);

    function flagReward() external view returns (uint256);

    function liquidateReward() external view returns (uint256);

    function rateStalePeriod() external view returns (uint256);

    function exchangeFeeRate(bytes32 currencyKey) external view returns (uint256);

    function minimumStakeTime() external view returns (uint256);

    function debtSnapshotStaleTime() external view returns (uint256);

    function aggregatorWarningFlags() external view returns (address);

    function tradingRewardsEnabled() external view returns (bool);

    function wrapperMaxTokenAmount(address wrapper) external view returns (uint256);

    function wrapperMintFeeRate(address wrapper) external view returns (int256);

    function wrapperBurnFeeRate(address wrapper) external view returns (int256);

    function etherWrapperMaxETH() external view returns (uint256);

    function etherWrapperBurnFeeRate() external view returns (uint256);

    function etherWrapperMintFeeRate() external view returns (uint256);

    function interactionDelay(address collateral) external view returns (uint256);

    function atomicMaxVolumePerBlock() external view returns (uint256);

    function atomicTwapWindow() external view returns (uint256);

    function atomicEquivalentForDexPricing(bytes32 currencyKey) external view returns (address);

    function atomicExchangeFeeRate(bytes32 currencyKey) external view returns (uint256);

    function atomicVolatilityConsiderationWindow(bytes32 currencyKey) external view returns (uint256);

    function atomicVolatilityUpdateThreshold(bytes32 currencyKey) external view returns (uint256);

    function pureChainlinkPriceForAtomicSwapsEnabled(bytes32 currencyKey) external view returns (bool);
}
