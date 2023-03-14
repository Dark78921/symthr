pragma solidity >=0.4.24;

// https://docs.synthetix.io/contracts/source/interfaces/isupplyschedule
interface ISupplySchedule {
    // Views
    function mintableSupply() external view returns (uint256);

    function isMintable() external view returns (bool);

    function minterReward() external view returns (uint256);

    // Mutative functions
    function recordMintEvent(uint256 supplyMinted) external returns (uint256);
}
