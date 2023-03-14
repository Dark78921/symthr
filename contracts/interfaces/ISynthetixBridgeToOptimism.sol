pragma solidity >=0.4.24;
pragma experimental ABIEncoderV2;

interface ISynthetixBridgeToOptimism {
    function closeFeePeriod(uint256 snxBackedDebt, uint256 debtSharesSupply) external;

    function migrateEscrow(uint256[][] calldata entryIDs) external;

    function depositReward(uint256 amount) external;

    function depositAndMigrateEscrow(uint256 depositAmount, uint256[][] calldata entryIDs) external;
}
