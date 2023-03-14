pragma solidity >=0.4.24;

// https://docs.synthetix.io/contracts/source/interfaces/irewardescrow
interface IRewardEscrow {
    // Views
    function balanceOf(address account) external view returns (uint256);

    function numVestingEntries(address account) external view returns (uint256);

    function totalEscrowedAccountBalance(address account) external view returns (uint256);

    function totalVestedAccountBalance(address account) external view returns (uint256);

    function getVestingScheduleEntry(address account, uint256 index) external view returns (uint256[2] memory);

    function getNextVestingIndex(address account) external view returns (uint256);

    // Mutative functions
    function appendVestingEntry(address account, uint256 quantity) external;

    function vest() external;
}
