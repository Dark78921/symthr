pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

// Internal references
import "./interfaces/IFuturesMarket.sol";
import "./interfaces/IFuturesMarketBaseTypes.sol";
import "./interfaces/IFuturesMarketManager.sol";
import "./interfaces/IFuturesMarketSettings.sol";
import "./interfaces/IAddressResolver.sol";

// https://docs.synthetix.io/contracts/source/contracts/FuturesMarketData
// A utility contract to allow the front end to query market data in a single call.
contract FuturesMarketData {
    /* ========== TYPES ========== */

    struct FuturesGlobals {
        uint256 minInitialMargin;
        uint256 liquidationFeeRatio;
        uint256 liquidationBufferRatio;
        uint256 minKeeperFee;
    }

    struct MarketSummary {
        address market;
        bytes32 asset;
        bytes32 key;
        uint256 maxLeverage;
        uint256 price;
        uint256 marketSize;
        int256 marketSkew;
        uint256 marketDebt;
        int256 currentFundingRate;
        FeeRates feeRates;
    }

    struct MarketLimits {
        uint256 maxLeverage;
        uint256 maxMarketValueUSD;
    }

    struct Sides {
        uint256 long;
        uint256 short;
    }

    struct MarketSizeDetails {
        uint256 marketSize;
        FuturesMarketData.Sides sides;
        uint256 marketDebt;
        int256 marketSkew;
    }

    struct PriceDetails {
        uint256 price;
        bool invalid;
    }

    struct FundingParameters {
        uint256 maxFundingRate;
        uint256 skewScaleUSD;
    }

    struct FeeRates {
        uint256 takerFee;
        uint256 makerFee;
        uint256 takerFeeNextPrice;
        uint256 makerFeeNextPrice;
    }

    struct FundingDetails {
        int256 currentFundingRate;
        int256 unrecordedFunding;
        uint256 fundingLastRecomputed;
    }

    struct MarketData {
        address market;
        bytes32 baseAsset;
        bytes32 marketKey;
        FuturesMarketData.FeeRates feeRates;
        FuturesMarketData.MarketLimits limits;
        FuturesMarketData.FundingParameters fundingParameters;
        FuturesMarketData.MarketSizeDetails marketSizeDetails;
        FuturesMarketData.PriceDetails priceDetails;
    }

    struct PositionData {
        IFuturesMarketBaseTypes.Position position;
        int256 notionalValue;
        int256 profitLoss;
        int256 accruedFunding;
        uint256 remainingMargin;
        uint256 accessibleMargin;
        uint256 liquidationPrice;
        bool canLiquidatePosition;
    }

    /* ========== STORAGE VARIABLES ========== */

    IAddressResolver public resolverProxy;

    /* ========== CONSTRUCTOR ========== */

    constructor(IAddressResolver _resolverProxy) public {
        resolverProxy = _resolverProxy;
    }

    /* ========== VIEWS ========== */

    function _futuresMarketManager() internal view returns (IFuturesMarketManager) {
        return
            IFuturesMarketManager(
                resolverProxy.requireAndGetAddress("FuturesMarketManager", "Missing FuturesMarketManager Address")
            );
    }

    function _futuresMarketSettings() internal view returns (IFuturesMarketSettings) {
        return
            IFuturesMarketSettings(
                resolverProxy.requireAndGetAddress("FuturesMarketSettings", "Missing FuturesMarketSettings Address")
            );
    }

    function globals() external view returns (FuturesGlobals memory) {
        IFuturesMarketSettings settings = _futuresMarketSettings();
        return
            FuturesGlobals({
                minInitialMargin: settings.minInitialMargin(),
                liquidationFeeRatio: settings.liquidationFeeRatio(),
                liquidationBufferRatio: settings.liquidationBufferRatio(),
                minKeeperFee: settings.minKeeperFee()
            });
    }

    function parameters(bytes32 marketKey) external view returns (IFuturesMarketSettings.Parameters memory) {
        return _parameters(marketKey);
    }

    function _parameters(bytes32 marketKey) internal view returns (IFuturesMarketSettings.Parameters memory) {
        (
            uint256 takerFee,
            uint256 makerFee,
            uint256 takerFeeNextPrice,
            uint256 makerFeeNextPrice,
            uint256 nextPriceConfirmWindow,
            uint256 maxLeverage,
            uint256 maxMarketValueUSD,
            uint256 maxFundingRate,
            uint256 skewScaleUSD
        ) = _futuresMarketSettings().parameters(marketKey);
        return
            IFuturesMarketSettings.Parameters(
                takerFee,
                makerFee,
                takerFeeNextPrice,
                makerFeeNextPrice,
                nextPriceConfirmWindow,
                maxLeverage,
                maxMarketValueUSD,
                maxFundingRate,
                skewScaleUSD
            );
    }

    function _marketSummaries(address[] memory markets) internal view returns (MarketSummary[] memory) {
        uint256 numMarkets = markets.length;
        MarketSummary[] memory summaries = new MarketSummary[](numMarkets);
        for (uint256 i; i < numMarkets; i++) {
            IFuturesMarket market = IFuturesMarket(markets[i]);
            bytes32 marketKey = market.marketKey();
            bytes32 baseAsset = market.baseAsset();
            IFuturesMarketSettings.Parameters memory params = _parameters(marketKey);

            (uint256 price, ) = market.assetPrice();
            (uint256 debt, ) = market.marketDebt();

            summaries[i] = MarketSummary(
                address(market),
                baseAsset,
                marketKey,
                params.maxLeverage,
                price,
                market.marketSize(),
                market.marketSkew(),
                debt,
                market.currentFundingRate(),
                FeeRates(params.takerFee, params.makerFee, params.takerFeeNextPrice, params.makerFeeNextPrice)
            );
        }

        return summaries;
    }

    function marketSummaries(address[] calldata markets) external view returns (MarketSummary[] memory) {
        return _marketSummaries(markets);
    }

    function marketSummariesForKeys(bytes32[] calldata marketKeys) external view returns (MarketSummary[] memory) {
        return _marketSummaries(_futuresMarketManager().marketsForKeys(marketKeys));
    }

    function allMarketSummaries() external view returns (MarketSummary[] memory) {
        return _marketSummaries(_futuresMarketManager().allMarkets());
    }

    function _fundingParameters(IFuturesMarketSettings.Parameters memory params)
        internal
        pure
        returns (FundingParameters memory)
    {
        return FundingParameters(params.maxFundingRate, params.skewScaleUSD);
    }

    function _marketSizes(IFuturesMarket market) internal view returns (Sides memory) {
        (uint256 long, uint256 short) = market.marketSizes();
        return Sides(long, short);
    }

    function _marketDetails(IFuturesMarket market) internal view returns (MarketData memory) {
        (uint256 price, bool invalid) = market.assetPrice();
        (uint256 marketDebt, ) = market.marketDebt();
        bytes32 baseAsset = market.baseAsset();
        bytes32 marketKey = market.marketKey();

        IFuturesMarketSettings.Parameters memory params = _parameters(marketKey);

        return
            MarketData(
                address(market),
                baseAsset,
                marketKey,
                FeeRates(params.takerFee, params.makerFee, params.takerFeeNextPrice, params.makerFeeNextPrice),
                MarketLimits(params.maxLeverage, params.maxMarketValueUSD),
                _fundingParameters(params),
                MarketSizeDetails(market.marketSize(), _marketSizes(market), marketDebt, market.marketSkew()),
                PriceDetails(price, invalid)
            );
    }

    function marketDetails(IFuturesMarket market) external view returns (MarketData memory) {
        return _marketDetails(market);
    }

    function marketDetailsForKey(bytes32 marketKey) external view returns (MarketData memory) {
        return _marketDetails(IFuturesMarket(_futuresMarketManager().marketForKey(marketKey)));
    }

    function _position(IFuturesMarket market, address account) internal view returns (IFuturesMarketBaseTypes.Position memory) {
        (
            uint64 positionId,
            uint64 positionEntryIndex,
            uint128 positionMargin,
            uint128 positionEntryPrice,
            int128 positionSize
        ) = market.positions(account);
        return IFuturesMarketBaseTypes.Position(positionId, positionEntryIndex, positionMargin, positionEntryPrice, positionSize);
    }

    function _notionalValue(IFuturesMarket market, address account) internal view returns (int256) {
        (int256 value, ) = market.notionalValue(account);
        return value;
    }

    function _profitLoss(IFuturesMarket market, address account) internal view returns (int256) {
        (int256 value, ) = market.profitLoss(account);
        return value;
    }

    function _accruedFunding(IFuturesMarket market, address account) internal view returns (int256) {
        (int256 value, ) = market.accruedFunding(account);
        return value;
    }

    function _remainingMargin(IFuturesMarket market, address account) internal view returns (uint256) {
        (uint256 value, ) = market.remainingMargin(account);
        return value;
    }

    function _accessibleMargin(IFuturesMarket market, address account) internal view returns (uint256) {
        (uint256 value, ) = market.accessibleMargin(account);
        return value;
    }

    function _liquidationPrice(IFuturesMarket market, address account) internal view returns (uint256) {
        (uint256 liquidationPrice, ) = market.liquidationPrice(account);
        return liquidationPrice;
    }

    function _positionDetails(IFuturesMarket market, address account) internal view returns (PositionData memory) {
        return
            PositionData(
                _position(market, account),
                _notionalValue(market, account),
                _profitLoss(market, account),
                _accruedFunding(market, account),
                _remainingMargin(market, account),
                _accessibleMargin(market, account),
                _liquidationPrice(market, account),
                market.canLiquidate(account)
            );
    }

    function positionDetails(IFuturesMarket market, address account) external view returns (PositionData memory) {
        return _positionDetails(market, account);
    }

    function positionDetailsForMarketKey(bytes32 marketKey, address account) external view returns (PositionData memory) {
        return _positionDetails(IFuturesMarket(_futuresMarketManager().marketForKey(marketKey)), account);
    }
}
