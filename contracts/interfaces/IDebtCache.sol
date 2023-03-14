pragma solidity >=0.4.24;

import "./IIssuer.sol";

interface IDebtCache {
    // Views

    function cachedDebt() external view returns (uint256);

    function cachedSynthDebt(bytes32 currencyKey) external view returns (uint256);

    function cacheTimestamp() external view returns (uint256);

    function cacheInvalid() external view returns (bool);

    function cacheStale() external view returns (bool);

    function isInitialized() external view returns (bool);

    function currentSynthDebts(bytes32[] calldata currencyKeys)
        external
        view
        returns (
            uint256[] memory debtValues,
            uint256 futuresDebt,
            uint256 excludedDebt,
            bool anyRateIsInvalid
        );

    function cachedSynthDebts(bytes32[] calldata currencyKeys) external view returns (uint256[] memory debtValues);

    function totalNonSnxBackedDebt() external view returns (uint256 excludedDebt, bool isInvalid);

    function currentDebt() external view returns (uint256 debt, bool anyRateIsInvalid);

    function cacheInfo()
        external
        view
        returns (
            uint256 debt,
            uint256 timestamp,
            bool isInvalid,
            bool isStale
        );

    function excludedIssuedDebts(bytes32[] calldata currencyKeys) external view returns (uint256[] memory excludedDebts);

    // Mutative functions

    function updateCachedSynthDebts(bytes32[] calldata currencyKeys) external;

    function updateCachedSynthDebtWithRate(bytes32 currencyKey, uint256 currencyRate) external;

    function updateCachedSynthDebtsWithRates(bytes32[] calldata currencyKeys, uint256[] calldata currencyRates) external;

    function updateDebtCacheValidity(bool currentlyInvalid) external;

    function purgeCachedSynthDebt(bytes32 currencyKey) external;

    function takeDebtSnapshot() external;

    function recordExcludedDebtChange(bytes32 currencyKey, int256 delta) external;

    function updateCachedsUSDDebt(int256 amount) external;

    function importExcludedIssuedDebts(IDebtCache prevDebtCache, IIssuer prevIssuer) external;
}
