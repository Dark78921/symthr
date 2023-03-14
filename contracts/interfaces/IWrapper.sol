pragma solidity >=0.4.24;

import "./IERC20.sol";

// https://docs.synthetix.io/contracts/source/interfaces/iwrapper
interface IWrapper {
    function mint(uint256 amount) external;

    function burn(uint256 amount) external;

    function capacity() external view returns (uint256);

    function totalIssuedSynths() external view returns (uint256);

    function calculateMintFee(uint256 amount) external view returns (uint256, bool);

    function calculateBurnFee(uint256 amount) external view returns (uint256, bool);

    function maxTokenAmount() external view returns (uint256);

    function mintFeeRate() external view returns (int256);

    function burnFeeRate() external view returns (int256);
}
