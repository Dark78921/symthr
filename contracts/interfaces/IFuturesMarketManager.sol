pragma solidity ^0.5.16;

interface IFuturesMarketManager {
    function markets(uint256 index, uint256 pageSize) external view returns (address[] memory);

    function numMarkets() external view returns (uint256);

    function allMarkets() external view returns (address[] memory);

    function marketForKey(bytes32 marketKey) external view returns (address);

    function marketsForKeys(bytes32[] calldata marketKeys) external view returns (address[] memory);

    function totalDebt() external view returns (uint256 debt, bool isInvalid);
}
