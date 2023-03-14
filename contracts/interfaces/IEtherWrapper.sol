pragma solidity >=0.4.24;

import "./IWETH.sol";

// https://docs.synthetix.io/contracts/source/interfaces/ietherwrapper
contract IEtherWrapper {
    function mint(uint256 amount) external;

    function burn(uint256 amount) external;

    function distributeFees() external;

    function capacity() external view returns (uint256);

    function getReserves() external view returns (uint256);

    function totalIssuedSynths() external view returns (uint256);

    function calculateMintFee(uint256 amount) public view returns (uint256);

    function calculateBurnFee(uint256 amount) public view returns (uint256);

    function maxETH() public view returns (uint256);

    function mintFeeRate() public view returns (uint256);

    function burnFeeRate() public view returns (uint256);

    function weth() public view returns (IWETH);
}
