pragma solidity >=0.4.24;

interface IIssuerInternalDebtCache {
    function updateCachedSynthDebtWithRate(bytes32 currencyKey, uint256 currencyRate) external;

    function updateCachedSynthDebtsWithRates(bytes32[] calldata currencyKeys, uint256[] calldata currencyRates) external;

    function updateDebtCacheValidity(bool currentlyInvalid) external;

    function totalNonSnxBackedDebt() external view returns (uint256 excludedDebt, bool isInvalid);

    function cacheInfo()
        external
        view
        returns (
            uint256 cachedDebt,
            uint256 timestamp,
            bool isInvalid,
            bool isStale
        );

    function updateCachedsUSDDebt(int256 amount) external;
}
