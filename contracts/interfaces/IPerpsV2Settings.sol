pragma solidity ^0.5.16;

interface IPerpsV2Settings {
    struct Parameters {
        uint256 baseFee;
        uint256 baseFeeNextPrice;
        uint256 nextPriceConfirmWindow;
        uint256 maxLeverage;
        uint256 maxSingleSideValueUSD;
        uint256 maxFundingRate;
        uint256 skewScaleUSD;
    }

    function baseFee(bytes32 _marketKey) external view returns (uint256);

    function baseFeeNextPrice(bytes32 _marketKey) external view returns (uint256);

    function nextPriceConfirmWindow(bytes32 _marketKey) external view returns (uint256);

    function maxLeverage(bytes32 _marketKey) external view returns (uint256);

    function maxSingleSideValueUSD(bytes32 _marketKey) external view returns (uint256);

    function maxFundingRate(bytes32 _marketKey) external view returns (uint256);

    function skewScaleUSD(bytes32 _marketKey) external view returns (uint256);

    function parameters(bytes32 _marketKey)
        external
        view
        returns (
            uint256 _baseFee,
            uint256 _baseFeeNextPrice,
            uint256 _nextPriceConfirmWindow,
            uint256 _maxLeverage,
            uint256 _maxSingleSideValueUSD,
            uint256 _maxFundingRate,
            uint256 _skewScaleUSD
        );

    function minKeeperFee() external view returns (uint256);

    function liquidationFeeRatio() external view returns (uint256);

    function liquidationBufferRatio() external view returns (uint256);

    function minInitialMargin() external view returns (uint256);
}
