pragma solidity >=0.4.24;

interface ICollateralEth {
    function open(uint256 amount, bytes32 currency) external payable returns (uint256 id);

    function close(uint256 id) external returns (uint256 amount, uint256 collateral);

    function deposit(address borrower, uint256 id) external payable returns (uint256 principal, uint256 collateral);

    function withdraw(uint256 id, uint256 amount) external returns (uint256 principal, uint256 collateral);

    function repay(
        address borrower,
        uint256 id,
        uint256 amount
    ) external returns (uint256 principal, uint256 collateral);

    function draw(uint256 id, uint256 amount) external returns (uint256 principal, uint256 collateral);

    function liquidate(
        address borrower,
        uint256 id,
        uint256 amount
    ) external;

    function claim(uint256 amount) external;
}
