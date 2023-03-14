pragma solidity ^0.5.16;

// Inheritance
import "./BaseWrappedSynthr.sol";
import "../SafeDecimalMath.sol";

// Internal references
import "../interfaces/IRewardEscrow.sol";
import "../interfaces/IRewardEscrowV2.sol";
import "../interfaces/ISupplySchedule.sol";
import "../interfaces/IExchangeRates.sol";

import "../libraries/TransferHelper.sol";

// https://docs.synthetix.io/contracts/source/contracts/synthetix
contract WrappedSynthr is BaseWrappedSynthr {
    using SafeDecimalMath for uint256;
    bytes32 public constant CONTRACT_NAME = "Synthetix";

    // ========== ADDRESS RESOLVER CONFIGURATION ==========
    bytes32 private constant CONTRACT_REWARD_ESCROW = "RewardEscrow";
    bytes32 private constant CONTRACT_REWARDESCROW_V2 = "RewardEscrowV2";
    bytes32 private constant CONTRACT_SUPPLYSCHEDULE = "SupplySchedule";
    bytes32 private constant CONTRACT_EXRATES = "ExchangeRates";

    mapping(bytes32 => mapping(address => uint256)) public collateralByIssuer;

    // ========== CONSTRUCTOR ==========

    constructor(
        address payable _proxy,
        TokenState _tokenState,
        address _owner,
        uint256 _totalSupply,
        address _resolver
    ) public BaseWrappedSynthr(_proxy, _tokenState, _owner, _totalSupply, _resolver) {}

    function resolverAddressesRequired() public view returns (bytes32[] memory addresses) {
        bytes32[] memory existingAddresses = BaseWrappedSynthr.resolverAddressesRequired();
        bytes32[] memory newAddresses = new bytes32[](4);
        newAddresses[0] = CONTRACT_REWARD_ESCROW;
        newAddresses[1] = CONTRACT_REWARDESCROW_V2;
        newAddresses[2] = CONTRACT_SUPPLYSCHEDULE;
        newAddresses[3] = CONTRACT_EXRATES;
        return combineArrays(existingAddresses, newAddresses);
    }

    // ========== VIEWS ==========

    function rewardEscrow() internal view returns (IRewardEscrow) {
        return IRewardEscrow(requireAndGetAddress(CONTRACT_REWARD_ESCROW));
    }

    function rewardEscrowV2() internal view returns (IRewardEscrowV2) {
        return IRewardEscrowV2(requireAndGetAddress(CONTRACT_REWARDESCROW_V2));
    }

    function supplySchedule() internal view returns (ISupplySchedule) {
        return ISupplySchedule(requireAndGetAddress(CONTRACT_SUPPLYSCHEDULE));
    }

    function exchangeRates() internal view returns (IExchangeRates) {
        return IExchangeRates(requireAndGetAddress(CONTRACT_EXRATES));
    }

    // ========== OVERRIDDEN FUNCTIONS ==========

    function balanceOf(address account) external view returns (uint256) {
        uint256 synthrBalance;
        for (uint256 ii = 0; ii < availableCollateralCurrencies.length; ii++) {
            bytes32 _collateralCurrencyKey = collateralByAddress[availableCollateralCurrencies[ii]];
            if (collateralByIssuer[_collateralCurrencyKey][account] > 0) {
                (uint256 collateralRate, ) = exchangeRates().rateAndInvalid(_collateralCurrencyKey);
                synthrBalance += collateralByIssuer[_collateralCurrencyKey][account].multiplyDecimal(collateralRate);
            }
        }
        return synthrBalance;
    }

    function exchangeWithVirtual(
        bytes32 sourceCurrencyKey,
        uint256 sourceAmount,
        bytes32 destinationCurrencyKey,
        bytes32 trackingCode
    )
        external
        exchangeActive(sourceCurrencyKey, destinationCurrencyKey)
        optionalProxy
        returns (uint256 amountReceived, IVirtualSynth vSynth)
    {
        return
            exchanger().exchange(
                messageSender,
                messageSender,
                sourceCurrencyKey,
                sourceAmount,
                destinationCurrencyKey,
                messageSender,
                true,
                messageSender,
                trackingCode
            );
    }

    // SIP-140 The initiating user of this exchange will receive the proceeds of the exchange
    // Note: this function may have unintended consequences if not understood correctly. Please
    // read SIP-140 for more information on the use-case
    function exchangeWithTrackingForInitiator(
        bytes32 sourceCurrencyKey,
        uint256 sourceAmount,
        bytes32 destinationCurrencyKey,
        address rewardAddress,
        bytes32 trackingCode
    ) external exchangeActive(sourceCurrencyKey, destinationCurrencyKey) optionalProxy returns (uint256 amountReceived) {
        (amountReceived, ) = exchanger().exchange(
            messageSender,
            messageSender,
            sourceCurrencyKey,
            sourceAmount,
            destinationCurrencyKey,
            // solhint-disable avoid-tx-origin
            tx.origin,
            false,
            rewardAddress,
            trackingCode
        );
    }

    function exchangeAtomically(
        bytes32 sourceCurrencyKey,
        uint256 sourceAmount,
        bytes32 destinationCurrencyKey,
        bytes32 trackingCode,
        uint256 minAmount
    ) external exchangeActive(sourceCurrencyKey, destinationCurrencyKey) optionalProxy returns (uint256 amountReceived) {
        return
            exchanger().exchangeAtomically(
                messageSender,
                sourceCurrencyKey,
                sourceAmount,
                destinationCurrencyKey,
                messageSender,
                trackingCode,
                minAmount
            );
    }

    function settle(bytes32 currencyKey)
        external
        optionalProxy
        returns (
            uint256 reclaimed,
            uint256 refunded,
            uint256 numEntriesSettled
        )
    {
        return exchanger().settle(messageSender, currencyKey);
    }

    function _mint(uint256 _amount) internal returns (bool) {
        emitTransfer(address(0), msg.sender, _amount);

        // Increase total supply by minted amount
        totalSupply = totalSupply.add(_amount);

        return true;
    }

    function _burn(uint256 _amount) internal returns (bool) {
        emitTransfer(messageSender, address(0), _amount);

        // Increase total supply by minted amount
        totalSupply = totalSupply.sub(_amount);

        return true;
    }

    function issueSynths(
        bytes32 _collateralKey,
        uint256 _collateralAmount,
        uint256 _synthToMint
    ) external payable issuanceActive optionalProxy {
        require(collateralCurrency[_collateralKey] != address(0), "No Collateral Currency exists.");
        if (_collateralKey == "ETH") {
            require(msg.value >= _collateralAmount, "Synthr: insufficient eth amount");
            if (msg.value > _collateralAmount) {
                (bool success, ) = messageSender.call.value(msg.value - _collateralAmount)("");
                require(success, "Transfer failed");
            }
        } else {
            TransferHelper.safeTransferFrom(collateralCurrency[_collateralKey], messageSender, address(this), _collateralAmount);
        }

        collateralByIssuer[_collateralKey][messageSender] += _collateralAmount;

        (uint256 collateralRate, ) = exchangeRates().rateAndInvalid(_collateralKey);
        uint256 synthrToMint = _collateralAmount.multiplyDecimal(collateralRate);
        bool isSucceed = _mint(synthrToMint);
        require(isSucceed, "Mint Synthr failed");

        return issuer().issueSynths(messageSender, _synthToMint);
    }

    function withdrawCollateral(
        bytes32 _collateralKey,
        uint256 _collateralAmount
    ) external issuanceActive optionalProxy {
        require(collateralCurrency[_collateralKey] != address(0), "No Collateral Currency exists.");
        require(collateralByIssuer[_collateralKey][messageSender] >= _collateralAmount, "Insufficient Collateral Balance to burn.");
        require(_collateralAmount <= issuer().checkFreeCollateral(messageSender, _collateralKey), "Overflow free collateral.");
        if (_collateralKey == "ETH") {
            require(address(this).balance >= _collateralAmount, "Insufficient ETH balance to burn.");
            TransferHelper.safeTransferETH(messageSender, _collateralAmount);
        } else {
            require(
                IERC20(collateralCurrency[_collateralKey]).balanceOf(address(this)) >= _collateralAmount,
                "Insufficient Collateral Balance to burn on Contract."
            );
            TransferHelper.safeTransfer(collateralCurrency[_collateralKey], messageSender, _collateralAmount);
        }

        collateralByIssuer[_collateralKey][messageSender] -= _collateralAmount;
        (uint256 collateralRate, ) = exchangeRates().rateAndInvalid(_collateralKey);
        uint256 synthrToBurn = _collateralAmount.multiplyDecimal(collateralRate);
        bool isSucceed = _burn(synthrToBurn);
        require(isSucceed, "Burn Synthr failed.");
        emit WithdrawCollateral(messageSender, _collateralKey, collateralCurrency[_collateralKey], _collateralAmount, synthrToBurn);
    }

    /* Once off function for SIP-60 to migrate SNX balances in the RewardEscrow contract
     * To the new RewardEscrowV2 contract
     */
    function migrateEscrowBalanceToRewardEscrowV2() external onlyOwner {
        // Record balanceOf(RewardEscrow) contract
        uint256 rewardEscrowBalance = tokenState.balanceOf(address(rewardEscrow()));

        // transfer all of RewardEscrow's balance to RewardEscrowV2
        // _internalTransfer emits the transfer event
        _internalTransfer(address(rewardEscrow()), address(rewardEscrowV2()), rewardEscrowBalance);
    }

    // ========== EVENTS ==========
    event WithdrawCollateral(address from, bytes32 collateralKey, address collateralCurrency, uint256 collateralAmount, uint256 synthrToBurn);

    event AtomicSynthExchange(
        address indexed account,
        bytes32 fromCurrencyKey,
        uint256 fromAmount,
        bytes32 toCurrencyKey,
        uint256 toAmount,
        address toAddress
    );
    bytes32 internal constant ATOMIC_SYNTH_EXCHANGE_SIG =
        keccak256("AtomicSynthExchange(address,bytes32,uint256,bytes32,uint256,address)");

    function emitAtomicSynthExchange(
        address account,
        bytes32 fromCurrencyKey,
        uint256 fromAmount,
        bytes32 toCurrencyKey,
        uint256 toAmount,
        address toAddress
    ) external onlyExchanger {
        proxy._emit(
            abi.encode(fromCurrencyKey, fromAmount, toCurrencyKey, toAmount, toAddress),
            2,
            ATOMIC_SYNTH_EXCHANGE_SIG,
            addressToBytes32(account),
            0,
            0
        );
    }
}
