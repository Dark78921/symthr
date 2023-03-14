pragma solidity ^0.5.16;

// Inheritance
import "./PerpsV2MarketBase.sol";

/**
 * A mixin that implements vairous useful views that are used externally but
 * aren't used inside the core contract (so don't need to clutter the contract file)
 */
contract PerpsV2ViewsMixin is PerpsV2MarketBase {
    /*
     * Sizes of the long and short sides of the market (in sUSD)
     */
    function marketSizes() public view returns (uint256 long, uint256 short) {
        int256 size = int256(marketSize);
        int256 skew = marketSkew;
        return (_abs(size.add(skew).div(2)), _abs(size.sub(skew).div(2)));
    }

    /*
     * The debt contributed by this market to the overall system.
     * The total market debt is equivalent to the sum of remaining margins in all open positions.
     */
    function marketDebt() external view returns (uint256 debt, bool invalid) {
        (uint256 price, bool isInvalid) = assetPrice();
        return (_marketDebt(price), isInvalid);
    }

    /*
     * The current funding rate as determined by the market skew; this is returned as a percentage per day.
     * If this is positive, shorts pay longs, if it is negative, longs pay shorts.
     */
    function currentFundingRate() external view returns (int256) {
        (uint256 price, ) = assetPrice();
        return _currentFundingRate(price);
    }

    /*
     * The funding per base unit accrued since the funding rate was last recomputed, which has not yet
     * been persisted in the funding sequence.
     */
    function unrecordedFunding() external view returns (int256 funding, bool invalid) {
        (uint256 price, bool isInvalid) = assetPrice();
        return (_unrecordedFunding(price), isInvalid);
    }

    /*
     * The number of entries in the funding sequence.
     */
    function fundingSequenceLength() external view returns (uint256) {
        return fundingSequence.length;
    }

    /*
     * The notional value of a position is its size multiplied by the current price. Margin and leverage are ignored.
     */
    function notionalValue(address account) external view returns (int256 value, bool invalid) {
        (uint256 price, bool isInvalid) = assetPrice();
        return (_notionalValue(positions[account].size, price), isInvalid);
    }

    /*
     * The PnL of a position is the change in its notional value. Funding is not taken into account.
     */
    function profitLoss(address account) external view returns (int256 pnl, bool invalid) {
        (uint256 price, bool isInvalid) = assetPrice();
        return (_profitLoss(positions[account], price), isInvalid);
    }

    /*
     * The funding accrued in a position since it was opened; this does not include PnL.
     */
    function accruedFunding(address account) external view returns (int256 funding, bool invalid) {
        (uint256 price, bool isInvalid) = assetPrice();
        return (_accruedFunding(positions[account], price), isInvalid);
    }

    /*
     * The initial margin plus profit and funding; returns zero balance if losses exceed the initial margin.
     */
    function remainingMargin(address account) external view returns (uint256 marginRemaining, bool invalid) {
        (uint256 price, bool isInvalid) = assetPrice();
        return (_remainingMargin(positions[account], price), isInvalid);
    }

    /*
     * The approximate amount of margin the user may withdraw given their current position; this underestimates the
     * true value slightly.
     */
    function accessibleMargin(address account) external view returns (uint256 marginAccessible, bool invalid) {
        (uint256 price, bool isInvalid) = assetPrice();
        return (_accessibleMargin(positions[account], price), isInvalid);
    }

    /*
     * The price at which a position is subject to liquidation, and the expected liquidation fees at that price; o
     * When they have just enough margin left to pay a liquidator, then they are liquidated.
     * If a position is long, then it is safe as long as the current price is above the liquidation price; if it is
     * short, then it is safe whenever the current price is below the liquidation price.
     * A position's accurate liquidation price can move around slightly due to accrued funding.
     */
    function approxLiquidationPriceAndFee(address account)
        external
        view
        returns (
            uint256 price,
            uint256 fee,
            bool invalid
        )
    {
        (uint256 aPrice, bool isInvalid) = assetPrice();
        uint256 liqPrice = _approxLiquidationPrice(positions[account], aPrice);
        // if position cannot be liquidated at any price (is not leveraged), return 0 as possible fee
        uint256 liqFee = liqPrice > 0 ? _liquidationFee(int256(positions[account].size), liqPrice) : 0;
        return (liqPrice, liqFee, isInvalid);
    }

    /*
     * True if and only if a position is ready to be liquidated.
     */
    function canLiquidate(address account) external view returns (bool) {
        (uint256 price, bool invalid) = assetPrice();
        return !invalid && _canLiquidate(positions[account], price);
    }

    /*
     * Reports the fee for submitting an order of a given size. Orders that increase the skew will be more
     * expensive than ones that decrease it. Dynamic fee is added according to the recent volatility
     * according to SIP-184.
     * @param sizeDelta size of the order in baseAsset units (negative numbers for shorts / selling)
     * @return fee in sUSD decimal, and invalid boolean flag for invalid rates or dynamic fee that is
     * too high due to recent volatility.
     */
    function orderFee(int256 sizeDelta) external view returns (uint256 fee, bool invalid) {
        (uint256 price, bool isInvalid) = assetPrice();
        (uint256 dynamicFeeRate, bool tooVolatile) = _dynamicFeeRate();
        TradeParams memory params = TradeParams({
            sizeDelta: sizeDelta,
            price: price,
            baseFee: _baseFee(marketKey),
            trackingCode: bytes32(0)
        });
        return (_orderFee(params, dynamicFeeRate), isInvalid || tooVolatile);
    }

    /*
     * Returns all new position details if a given order from `sender` was confirmed at the current price.
     */
    function postTradeDetails(int256 sizeDelta, address sender)
        external
        view
        returns (
            uint256 margin,
            int256 size,
            uint256 price,
            uint256 liqPrice,
            uint256 fee,
            Status status
        )
    {
        bool invalid;
        (price, invalid) = assetPrice();
        if (invalid) {
            return (0, 0, 0, 0, 0, Status.InvalidPrice);
        }

        TradeParams memory params = TradeParams({
            sizeDelta: sizeDelta,
            price: price,
            baseFee: _baseFee(marketKey),
            trackingCode: bytes32(0)
        });
        (Position memory newPosition, uint256 fee_, Status status_) = _postTradeDetails(positions[sender], params);

        liqPrice = _approxLiquidationPrice(newPosition, newPosition.lastPrice);
        return (newPosition.margin, newPosition.size, newPosition.lastPrice, liqPrice, fee_, status_);
    }

    /// helper methods calculates the approximate liquidation price
    function _approxLiquidationPrice(Position memory position, uint256 currentPrice) internal view returns (uint256) {
        int256 positionSize = int256(position.size);

        // short circuit
        if (positionSize == 0) {
            return 0;
        }

        // price = lastPrice + (liquidationMargin - margin) / positionSize - netAccrued
        int256 fundingPerUnit = _netFundingPerUnit(position.lastFundingIndex, currentPrice);

        // minimum margin beyond which position can be liqudiated
        uint256 liqMargin = _liquidationMargin(positionSize, currentPrice);

        // A position can be liquidated whenever:
        //     remainingMargin <= liquidationMargin
        // Hence, expanding the definition of remainingMargin the exact price
        // at which a position can first be liquidated is:
        //     margin + profitLoss + funding =  liquidationMargin
        //     substitute with: profitLoss = (price - last-price) * positionSize
        //     and also with: funding = netFundingPerUnit * positionSize
        //     we get: margin + (price - last-price) * positionSize + netFundingPerUnit * positionSize =  liquidationMargin
        //     moving around: price  = lastPrice + (liquidationMargin - margin) / positionSize - netFundingPerUnit
        int256 result = int256(position.lastPrice)
            .add(int256(liqMargin).sub(int256(position.margin)).divideDecimal(positionSize))
            .sub(fundingPerUnit);

        // If the user has leverage less than 1, their liquidation price may actually be negative; return 0 instead.
        return uint256(_max(0, result));
    }
}
