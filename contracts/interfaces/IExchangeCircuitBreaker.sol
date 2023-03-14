pragma solidity ^0.5.16;

// https://docs.synthetix.io/contracts/source/interfaces/IExchangeCircuitBreaker
interface IExchangeCircuitBreaker {
    // Views

    function exchangeRates() external view returns (address);

    function rateWithInvalid(bytes32 currencyKey) external view returns (uint256, bool);

    function priceDeviationThresholdFactor() external view returns (uint256);

    function isDeviationAboveThreshold(uint256 base, uint256 comparison) external view returns (bool);

    function lastExchangeRate(bytes32 currencyKey) external view returns (uint256);

    // Mutative functions
    function resetLastExchangeRate(bytes32[] calldata currencyKeys) external;

    function rateWithBreakCircuit(bytes32 currencyKey) external returns (uint256 lastValidRate, bool circuitBroken);
}
