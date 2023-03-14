pragma solidity >=0.4.24;

interface ICollateralManager {
    // Manager information
    function hasCollateral(address collateral) external view returns (bool);

    function isSynthManaged(bytes32 currencyKey) external view returns (bool);

    // State information
    function long(bytes32 synth) external view returns (uint256 amount);

    function short(bytes32 synth) external view returns (uint256 amount);

    function totalLong() external view returns (uint256 susdValue, bool anyRateIsInvalid);

    function totalShort() external view returns (uint256 susdValue, bool anyRateIsInvalid);

    function getBorrowRate() external view returns (uint256 borrowRate, bool anyRateIsInvalid);

    function getShortRate(bytes32 synth) external view returns (uint256 shortRate, bool rateIsInvalid);

    function getRatesAndTime(uint256 index)
        external
        view
        returns (
            uint256 entryRate,
            uint256 lastRate,
            uint256 lastUpdated,
            uint256 newIndex
        );

    function getShortRatesAndTime(bytes32 currency, uint256 index)
        external
        view
        returns (
            uint256 entryRate,
            uint256 lastRate,
            uint256 lastUpdated,
            uint256 newIndex
        );

    function exceedsDebtLimit(uint256 amount, bytes32 currency) external view returns (bool canIssue, bool anyRateIsInvalid);

    function areSynthsAndCurrenciesSet(bytes32[] calldata requiredSynthNamesInResolver, bytes32[] calldata synthKeys)
        external
        view
        returns (bool);

    function areShortableSynthsSet(bytes32[] calldata requiredSynthNamesInResolver, bytes32[] calldata synthKeys)
        external
        view
        returns (bool);

    // Loans
    function getNewLoanId() external returns (uint256 id);

    // Manager mutative
    function addCollaterals(address[] calldata collaterals) external;

    function removeCollaterals(address[] calldata collaterals) external;

    function addSynths(bytes32[] calldata synthNamesInResolver, bytes32[] calldata synthKeys) external;

    function removeSynths(bytes32[] calldata synths, bytes32[] calldata synthKeys) external;

    function addShortableSynths(bytes32[] calldata requiredSynthNamesInResolver, bytes32[] calldata synthKeys) external;

    function removeShortableSynths(bytes32[] calldata synths) external;

    // State mutative

    function incrementLongs(bytes32 synth, uint256 amount) external;

    function decrementLongs(bytes32 synth, uint256 amount) external;

    function incrementShorts(bytes32 synth, uint256 amount) external;

    function decrementShorts(bytes32 synth, uint256 amount) external;

    function accrueInterest(
        uint256 interestIndex,
        bytes32 currency,
        bool isShort
    ) external returns (uint256 difference, uint256 index);

    function updateBorrowRatesCollateral(uint256 rate) external;

    function updateShortRatesCollateral(bytes32 currency, uint256 rate) external;
}
