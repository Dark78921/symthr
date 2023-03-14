// const { expect } = require("chai")
// const { ethers, network } = require("hardhat")
// const { getBigNumber, getNumber } = require("../scripts/shared/utilities")
// const { BigNumber } = ethers
// const {
//   CURRENCY_KEYS, USDC, AGGREGATOR
// } = require("../scripts/shared/constants")
// const addressList = require("../scripts/shared/rinkeby.json");

// describe("Synthetix Exchange", function () {
//   before(async function () {
//     this.signers = await ethers.getSigners();
//     console.log('[signers]', this.signers[0].address)
//     this.Synthetix = await ethers.getContractFactory("Synthetix");
//     this.synthetix = await this.Synthetix.attach(addressList.Synthetix);

//     this.SynthetixProxy = await ethers.getContractFactory("ProxyERC20");
//     this.synthetixProxy = await this.SynthetixProxy.attach(addressList.SynthetixProxy);

//     this.sUSDProxy = await this.SynthetixProxy.attach(addressList.ProxyERC20sUSD);
//     this.sEURProxy = await this.SynthetixProxy.attach(addressList.ProxyERC20sEUR);
//     this.sETHProxy = await this.SynthetixProxy.attach(addressList.ProxyERC20sETH);

//     this.Exchanger = await ethers.getContractFactory("ExchangerWithFeeRecAlternatives", {
//       libraries: {
//         SafeDecimalMath: addressList.SafeDecimalMath
//       }
//     });
//     this.exchanger = await this.Exchanger.deploy(this.signers[0].address, addressList.AddressResolver);

//     this.ExchangeRates = await ethers.getContractFactory("ExchangeRatesWithDexPricing", {
//       libraries: {
//         SafeDecimalMath: addressList.SafeDecimalMath
//       }
//     });
//     this.exchangeRates = await this.ExchangeRates.deploy(this.signers[0].address, addressList.AddressResolver)
//     // this.exchangeRates = await this.ExchangeRates.attach(addressList.ExchangeRatesWithDexPricing);
//     this.ExchangeState = await ethers.getContractFactory("ExchangeState");
//     this.exchangeState = await this.ExchangeState.attach(addressList.ExchangeState)

//     await this.exchangeState.setAssociatedContract(this.exchanger.address)

//     // this.synthetix = await this.Synthetix.deploy(addressList.SynthetixProxy, addressList.TokenStateSNX, this.signers[0].address, 0, addressList.AddressResolver);

//     console.log('[exchangeRate address]', this.exchangeRates.address, this.exchanger.address)

//     this.Issuer = await ethers.getContractFactory("Issuer", {
//       libraries: {
//         SafeDecimalMath: addressList.SafeDecimalMath
//       }
//     });

//     this.issuer = await this.Issuer.attach(addressList.Issuer);

//     // await this.issuer.addSynth(addressList.SynthsETH);
//     // await this.issuer.addSynth(addressList.SynthsEUR);

//     const availableSynthCount = await this.issuer.availableSynthCount()
//     console.log('[availableSynthCount]', availableSynthCount.toString())

//     // this.issuer = await this.Issuer.deploy(this.signers[0].address, addressList.AddressResolver);

//     // await (await this.issuer.rebuildCache()).wait();

//     this.AddressResolver = await ethers.getContractFactory("AddressResolver");
//     this.addressResolver = await this.AddressResolver.attach(addressList.AddressResolver);
//     await this.addressResolver.importAddresses(['0x45786368616e6765720000000000000000000000000000000000000000000000', '0x45786368616e6765526174657300000000000000000000000000000000000000'], [this.exchanger.address, this.exchangeRates.address])

//     const rebuildContracts = [
//       "Synthetix", "SynthsUSD", "SynthsETH", "SynthsEUR", "DebtCache", "FeePool", "SynthetixDebtShare", "LiquidatorRewards", "Liquidator", "RewardEscrowV2", "SynthRedeemer", "CollateralManager", "WrapperFactory", "EtherWrapper", "FuturesMarketManager", "SynthetixBridgeToOptimism", "SynthsDASH", "SynthsBTC", "CollateralErc20"
//     ] //, "ExchangerWithFeeRecAlternatives", "ExchangeRatesWithDexPricing"

//     const rebuildAddr = rebuildContracts.map((item) => addressList[item])

//     const tx2 = await this.addressResolver.rebuildCaches(rebuildAddr);
//     // // console.log('Transaction was succeed with tx hash ', await tx2.wait());

//     // await (await this.issuer.addSynth(addressList.SynthsUSD)).wait();

//     await this.addressResolver.rebuildCaches([this.exchanger.address, this.exchangeRates.address])

//     await this.exchangeRates.addAggregator(CURRENCY_KEYS.SNX, addressList.SNXAggregator)
//     await this.exchangeRates.addAggregator(CURRENCY_KEYS.sETH, AGGREGATOR.sETH)
//     await this.exchangeRates.addAggregator(CURRENCY_KEYS.sEUR, AGGREGATOR.sEUR)
//     await this.exchangeRates.setDexPriceAggregator(addressList.DexPriceAggregatorUniswapV3)

//     const tx = await this.synthetixProxy.transfer(this.signers[1].address, ethers.utils.parseUnits("1000"));
//     const checkBalance = await this.synthetixProxy.balanceOf(this.signers[1].address);
//     console.log('[check balance]', checkBalance.toString());
//   })

//   describe("sUSD exchange Process", function () {
//     it("should exchange sUSD to sEUR", async function () {
//       console.log("[sUSD address check]", this.sUSDProxy.address);

//       await(await this.sUSDProxy.connect(this.signers[0]).approve(this.synthetix.address, ethers.constants.MaxUint256)).wait();
//       await(await this.sUSDProxy.connect(this.signers[0]).approve(addressList.Issuer, ethers.constants.MaxUint256)).wait();

//       const sUSDbalanceBefore = await this.sUSDProxy.balanceOf(this.signers[0].address);
//       console.log('[sUSDbalanceBefore]', sUSDbalanceBefore.toString())
//       const sEURbalanceBefore = await this.sEURProxy.balanceOf(this.signers[0].address);
//       console.log('[sEURbalanceBefore]', sEURbalanceBefore.toString())
//       const sETHbalanceBefore = await this.sETHProxy.balanceOf(this.signers[0].address);
//       console.log('[sETHbalanceBefore]', sETHbalanceBefore.toString())

//       const expectedAmount = await this.exchangeRates.effectiveAtomicValueAndRates(CURRENCY_KEYS.sUSD, ethers.utils.parseUnits("10"), CURRENCY_KEYS.sETH);

//       console.log("[expected amount]", expectedAmount.value.toString(), expectedAmount.systemValue.toString(), expectedAmount.systemDestinationRate.toString())

//       const tx = await(await this.synthetix.connect(this.signers[0]).exchangeAtomically(CURRENCY_KEYS.sUSD, ethers.utils.parseUnits("100"), CURRENCY_KEYS.sETH, ethers.constants.HashZero, expectedAmount.value)).wait();

//       console.log('[exchange transaction check]', tx.transactionHash)

//       const sUSDbalanceAfter = await this.sUSDProxy.balanceOf(this.signers[0].address);
//       console.log('[sUSDbalanceAfter]', sUSDbalanceAfter.toString())
//       const sEURbalanceAfter = await this.sEURProxy.balanceOf(this.signers[0].address);
//       console.log('[sEURbalanceAfter]', sEURbalanceAfter.toString())
//       const sETHbalanceAfter = await this.sETHProxy.balanceOf(this.signers[0].address);
//       console.log('[sETHbalanceAfter]', sETHbalanceAfter.toString())
//     })

//   })
// })
