const { expect } = require("chai")
const { ethers, network } = require("hardhat")
const { getBigNumber, getNumber, capFirst } = require("../scripts/shared/utilities")
const { BigNumber } = ethers
const { WETH_ADDRESS, Lib_ResolvedDelegateProxy, COLLATERAL_CURRENCIES } = require("../scripts/shared/constants")
const addressList = require("../scripts/shared/rinkeby.json")
const patterns = require("../scripts/shared/bytes32Patterns.json")

describe("Wrapped Synthr", function () {
  before(async function () {
    this.signers = await ethers.getSigners()
    this.owner = this.signers[0]

    this.IssuedSynthsAggregator = await ethers.getContractFactory("IssuedSynthsAggregator")
    this.issuedSynthsAggregator = await this.IssuedSynthsAggregator.deploy(this.owner.address)

    this.DebtRatioAggregator = await ethers.getContractFactory("DebtRatioAggregator")
    this.debtRatioAggregator = await this.DebtRatioAggregator.deploy(this.owner.address)

    this.SafeDecimalMath = await ethers.getContractFactory("SafeDecimalMath")
    this.safeDecimalMath = await this.SafeDecimalMath.deploy()

    this.AddressResolver = await ethers.getContractFactory("AddressResolver")
    this.addressResolver = await this.AddressResolver.deploy(this.owner.address)

    this.SynthetixProxy = await ethers.getContractFactory("ProxyERC20")
    this.synthetixProxy = await this.SynthetixProxy.deploy(this.owner.address)

    this.SynthetixTokenState = await ethers.getContractFactory("TokenState")
    this.synthetixTokenState = await this.SynthetixTokenState.deploy(this.owner.address, ethers.constants.AddressZero)

    this.Synthetix = await ethers.getContractFactory("WrappedSynthr")
    this.synthetix = await this.Synthetix.deploy(
      this.synthetixProxy.address,
      this.synthetixTokenState.address,
      this.owner.address,
      0,
      this.addressResolver.address,
    )

    await this.synthetixProxy.setTarget(this.synthetix.address)
    await this.synthetixTokenState.setAssociatedContract(this.synthetix.address)

    this.SyUSDProxy = await ethers.getContractFactory("ProxyERC20")
    this.syUSDProxy = await this.SyUSDProxy.deploy(this.owner.address)

    this.SyUSDTokenState = await ethers.getContractFactory("TokenState")
    this.syUSDTokenState = await this.SyUSDTokenState.deploy(this.owner.address, ethers.constants.AddressZero)

    this.SyUSD = await ethers.getContractFactory("MultiCollateralSynth")
    this.syUSD = await this.SyUSD.deploy(
      this.syUSDProxy.address,
      this.syUSDTokenState.address,
      "Synthr syUSD",
      "SyUSD",
      this.owner.address,
      "0x7355534400000000000000000000000000000000000000000000000000000000",
      ethers.utils.parseUnits("1000000"),
      this.addressResolver.address,
    )

    await this.syUSDProxy.setTarget(this.syUSD.address)
    await this.syUSDTokenState.setAssociatedContract(this.syUSD.address)

    this.SyDASHProxy = await ethers.getContractFactory("ProxyERC20")
    this.syDASHProxy = await this.SyDASHProxy.deploy(this.owner.address)

    this.SyDASHTokenState = await ethers.getContractFactory("TokenState")
    this.syDASHTokenState = await this.SyDASHTokenState.deploy(this.owner.address, ethers.constants.AddressZero)

    this.SyDASH = await ethers.getContractFactory("MultiCollateralSynth")
    this.syDASH = await this.SyDASH.deploy(
      this.syDASHProxy.address,
      this.syDASHTokenState.address,
      "Synthr syDASH",
      "SyDASH",
      this.owner.address,
      "0x7344415348000000000000000000000000000000000000000000000000000000",
      ethers.utils.parseUnits("1000000"),
      this.addressResolver.address,
    )

    await this.syDASHProxy.setTarget(this.syDASH.address)
    await this.syDASHTokenState.setAssociatedContract(this.syDASH.address)

    this.SyETHProxy = await ethers.getContractFactory("ProxyERC20")
    this.syETHProxy = await this.SyETHProxy.deploy(this.owner.address)

    this.SyETHTokenState = await ethers.getContractFactory("TokenState")
    this.syETHTokenState = await this.SyETHTokenState.deploy(this.owner.address, ethers.constants.AddressZero)

    this.SyETH = await ethers.getContractFactory("MultiCollateralSynth")
    this.syETH = await this.SyETH.deploy(
      this.syETHProxy.address,
      this.syETHTokenState.address,
      "Synthr syETH",
      "SyETH",
      this.owner.address,
      "0x7345544800000000000000000000000000000000000000000000000000000000",
      ethers.utils.parseUnits("1000000"),
      this.addressResolver.address,
    )

    await this.syETHProxy.setTarget(this.syETH.address)
    await this.syETHTokenState.setAssociatedContract(this.syETH.address)

    this.Issuer = await ethers.getContractFactory("SynthrIssuer", {
      libraries: {
        SafeDecimalMath: this.safeDecimalMath.address,
      },
    })
    this.issuer = await this.Issuer.deploy(this.owner.address, this.addressResolver.address)

    this.ExchangeRatesWithDexPricing = await ethers.getContractFactory("ExchangeRatesWithDexPricing", {
      libraries: {
        SafeDecimalMath: this.safeDecimalMath.address,
      },
    })
    this.exchangeRatesWithDexPricing = await this.ExchangeRatesWithDexPricing.deploy(
      this.owner.address,
      this.addressResolver.address,
    )

    this.FlexibleStorage = await ethers.getContractFactory("FlexibleStorage")
    this.flexibleStorage = await this.FlexibleStorage.deploy(this.addressResolver.address)

    this.DebtCache = await ethers.getContractFactory("DebtCache")
    this.debtCache = await this.DebtCache.deploy(this.owner.address, this.addressResolver.address)

    this.FeePoolProxy = await ethers.getContractFactory("Proxy")
    this.feePoolProxy = await this.FeePoolProxy.deploy(this.owner.address)

    this.FeePool = await ethers.getContractFactory("FeePool", {
      libraries: {
        SafeDecimalMath: this.safeDecimalMath.address,
      },
    })
    this.feePool = await this.FeePool.deploy(this.feePoolProxy.address, this.owner.address, this.addressResolver.address)
    await this.feePoolProxy.setTarget(this.feePool.address)

    this.FeePoolEternalStorage = await ethers.getContractFactory("FeePoolEternalStorage")
    this.feePoolEternalStorage = await this.FeePoolEternalStorage.deploy(this.owner.address, this.feePool.address)

    this.Exchanger = await ethers.getContractFactory("ExchangerWithFeeRecAlternatives", {
      libraries: {
        SafeDecimalMath: this.safeDecimalMath.address,
      },
    })
    this.exchanger = await this.Exchanger.deploy(this.owner.address, this.addressResolver.address)

    this.SynthetixDebtShare = await ethers.getContractFactory("SynthetixDebtShare")
    this.synthetixDebtShare = await this.SynthetixDebtShare.deploy(this.owner.address, this.addressResolver.address)

    this.LiquidatorRewards = await ethers.getContractFactory("LiquidatorRewards")
    this.liquidatorRewards = await this.LiquidatorRewards.deploy(this.owner.address, this.addressResolver.address)

    this.SystemStatus = await ethers.getContractFactory("SystemStatus")
    this.systemStatus = await this.SystemStatus.deploy(this.owner.address)

    // this.zeroAddress = ethers.constants.AddressZero;
    this.RewardEscrow = await ethers.getContractFactory("RewardEscrow")
    this.rewardEscrow = await this.RewardEscrow.deploy(this.owner.address, this.synthetix.address, this.feePool.address)

    this.RewardEscrowV2 = await ethers.getContractFactory("RewardEscrowV2", {
      libraries: {
        SafeDecimalMath: this.safeDecimalMath.address,
      },
    })
    this.rewardEscrowV2 = await this.RewardEscrowV2.deploy(this.owner.address, this.addressResolver.address)

    this.RewardsDistribution = await ethers.getContractFactory("RewardsDistribution")
    this.rewardsDistribution = await this.RewardsDistribution.deploy(
      this.owner.address,
      this.owner.address,
      this.synthetixProxy.address,
      this.rewardEscrow.address,
      this.feePoolProxy.address,
    )

    this.Liquidator = await ethers.getContractFactory("Liquidator", {
      libraries: {
        SafeDecimalMath: this.safeDecimalMath.address,
      },
    })
    this.liquidator = await this.Liquidator.deploy(this.owner.address, this.addressResolver.address)

    this.SynthetixEscrow = await ethers.getContractFactory("SynthetixEscrow")
    this.synthetixEscrow = await this.SynthetixEscrow.deploy(this.owner.address, this.synthetix.address)

    this.SupplySchedule = await ethers.getContractFactory("SupplySchedule")
    this.supplySchedule = await this.SupplySchedule.deploy(this.owner.address, 0, 22)
    await this.supplySchedule.setSynthetixProxy(this.synthetixProxy.address)

    this.EternalStorage = await ethers.getContractFactory("EternalStorage")
    this.eternalStorage = await this.EternalStorage.deploy(this.owner.address, ethers.constants.AddressZero)

    this.DelegateApprovals = await ethers.getContractFactory("DelegateApprovals")
    this.delegateApprovals = await this.DelegateApprovals.deploy(this.owner.address, this.eternalStorage.address)

    await this.eternalStorage.setAssociatedContract(this.delegateApprovals.address)

    this.SynthRedeemer = await ethers.getContractFactory("SynthRedeemer")
    this.synthRedeemer = await this.SynthRedeemer.deploy(this.addressResolver.address)

    this.CollateralManagerState = await ethers.getContractFactory("CollateralManagerState")
    this.collateralManagerState = await this.CollateralManagerState.deploy(this.owner.address, ethers.constants.AddressZero)

    const d = new Date()
    const currentTime = Math.floor(d.getTime() / 1000)
    this.CollateralManager = await ethers.getContractFactory("CollateralManager")
    this.collateralManager = await this.CollateralManager.deploy(
      this.collateralManagerState.address,
      this.owner.address,
      this.addressResolver.address,
      ethers.utils.parseUnits("90000000"),
      0,
      3168876,
      currentTime,
    )
    await this.collateralManagerState.setAssociatedContract(this.collateralManager.address)

    this.WrapperFactory = await ethers.getContractFactory("WrapperFactory", {
      libraries: {
        SafeDecimalMath: this.safeDecimalMath.address,
      },
    })
    this.wrapperFactory = await this.WrapperFactory.deploy(this.owner.address, this.addressResolver.address)

    this.EtherWrapper = await ethers.getContractFactory("EtherWrapper", {
      libraries: {
        SafeDecimalMath: this.safeDecimalMath.address,
      },
    })
    this.etherWrapper = await this.EtherWrapper.deploy(this.owner.address, this.addressResolver.address, WETH_ADDRESS.rinkeby)

    this.FuturesMarketManager = await ethers.getContractFactory("FuturesMarketManager")
    this.futuresMarketManager = await this.FuturesMarketManager.deploy(this.owner.address, this.addressResolver.address)

    this.SynthetixBridgeToOptimism = await ethers.getContractFactory("SynthetixBridgeToOptimism")
    this.synthetixBridgeToOptimism = await this.SynthetixBridgeToOptimism.deploy(this.owner.address, this.addressResolver.address)

    this.SynthetixBridgeEscrow = await ethers.getContractFactory("SynthetixBridgeEscrow")
    this.synthetixBridgeEscrow = await this.SynthetixBridgeEscrow.deploy(this.owner.address)

    this.SynthetixBridgeToBase = await ethers.getContractFactory("SynthetixBridgeToBase")
    this.synthetixBridgeToBase = await this.SynthetixBridgeToBase.deploy(this.owner.address, this.addressResolver.address)

    this.ExchangeState = await ethers.getContractFactory("ExchangeState")
    this.exchangeState = await this.ExchangeState.deploy(this.owner.address, this.exchanger.address)

    this.TradingRewards = await ethers.getContractFactory("TradingRewards")
    this.tradingRewards = await this.TradingRewards.deploy(this.owner.address, this.owner.address, this.addressResolver.address)

    this.ExchangeCircuitBreaker = await ethers.getContractFactory("ExchangeCircuitBreaker")
    this.exchangeCircuitBreaker = await this.ExchangeCircuitBreaker.deploy(this.owner.address, this.addressResolver.address)

    this.VirtualSynthMastercopy = await ethers.getContractFactory("VirtualSynthMastercopy")
    this.virtualSynthMastercopy = await this.VirtualSynthMastercopy.deploy()

    this.SystemSettingsLib = await ethers.getContractFactory("SystemSettingsLib", {
      libraries: {
        SafeDecimalMath: this.safeDecimalMath.address,
      },
    })
    this.systemSettingsLib = await this.SystemSettingsLib.deploy()

    this.SystemSettings = await ethers.getContractFactory("SystemSettings", {
      libraries: {
        SystemSettingsLib: this.systemSettingsLib.address,
      },
    })
    this.systemSettings = await this.SystemSettings.deploy(this.owner.address, this.addressResolver.address)

    this.SynthUtil = await ethers.getContractFactory("SynthUtil")
    this.synthUtil = await this.SynthUtil.deploy(this.addressResolver.address)

    this.Depot = await ethers.getContractFactory("Depot", {
      libraries: {
        SafeDecimalMath: this.safeDecimalMath.address,
      },
    })
    this.depot = await this.Depot.deploy(this.owner.address, this.owner.address, this.addressResolver.address)

    this.DappMaintenance = await ethers.getContractFactory("DappMaintenance")
    this.dappMaintenance = await this.DappMaintenance.deploy(this.owner.address)

    let bytesArr = Object.keys(patterns)
      .map((item) => patterns[item].bytes)
      .filter((item) => item !== "" && item !== "0x6578743a4d657373656e67657200000000000000000000000000000000000000")
    bytesArr = [...bytesArr, "0x6578743a4d657373656e67657200000000000000000000000000000000000000"]
    let contractArr = Object.keys(patterns)
      .filter(
        (item) =>
          patterns[item].bytes !== "" &&
          patterns[item].bytes !== "0x6578743a4d657373656e67657200000000000000000000000000000000000000",
      )
      .map((item) => this[capFirst(patterns[item].contractName)].address)
    contractArr = [...contractArr, Lib_ResolvedDelegateProxy.goerli]

    await this.addressResolver.importAddresses(bytesArr, contractArr)

    const rebuildContracts = [
      "Synthetix",
      "Issuer",
      "SyUSD",
      "SyETH",
      "DebtCache",
      "FeePool",
      "Exchanger",
      "ExchangeRatesWithDexPricing",
      "SynthetixDebtShare",
      "LiquidatorRewards",
      "Liquidator",
      "RewardEscrowV2",
      "SynthRedeemer",
      "CollateralManager",
      "WrapperFactory",
      "EtherWrapper",
      "SystemSettings",
      "FuturesMarketManager",
      "SynthetixBridgeToOptimism",
      "SyDASH",
    ]

    const rebuildAddr = rebuildContracts.map((item) => this[capFirst(item)].address)

    const tx = await (await this.addressResolver.rebuildCaches(rebuildAddr)).wait()
    console.log("Rebuild Transaction was succeed with tx hash ", await tx.transactionHash)

    await (await this.issuer.addSynth(this.syUSD.address)).wait()
    await (await this.issuer.addSynth(this.syETH.address)).wait()
    await (await this.issuer.addSynth(this.syDASH.address)).wait()

    await (
      await this.synthetix.addCollateralCurrency(COLLATERAL_CURRENCIES.ETH.currencyAddress, COLLATERAL_CURRENCIES.ETH.currencyKey)
    ).wait()
    await (
      await this.synthetix.addCollateralCurrency(
        COLLATERAL_CURRENCIES.USDT.currencyAddress,
        COLLATERAL_CURRENCIES.USDT.currencyKey,
      )
    ).wait()

    await (
      await this.exchangeRatesWithDexPricing.addAggregator(
        COLLATERAL_CURRENCIES.ETH.currencyKey,
        COLLATERAL_CURRENCIES.ETH.aggregator.goerli,
      )
    ).wait()

    await await this.systemSettings.setPriceDeviationThresholdFactor(ethers.utils.parseUnits("1.8"))
    await await this.systemSettings.setIssuanceRatio(ethers.utils.parseUnits("0.285714286"))

    const tx1 = await (
      await this.debtRatioAggregator.setAnswer(ethers.utils.parseUnits("1259936594381933626242374099", 0))
    ).wait()

    const tx2 = await (
      await this.debtRatioAggregator.setAnsweredInRound(ethers.utils.parseUnits("18446744073709556128", 0))
    ).wait()

    const tx3 = await (await this.debtRatioAggregator.setRoundId(ethers.utils.parseUnits("18446744073709556128", 0))).wait()

    const tx4 = await (await this.debtRatioAggregator.setUpdatedAt(currentTime)).wait()

    const tx5 = await (await this.issuedSynthsAggregator.setUpdatedAt(currentTime)).wait()
  })

  describe("Wrapped Synthr Minting Process", function () {
    it("should mint Wrapped Synthr", async function () {
      const balanceBefore = await this.synthetix.balanceOf(this.signers[1].address)
      expect(balanceBefore).to.be.equal(0)

      const sUSDbalanceBefore = await this.syUSDProxy.balanceOf(this.signers[1].address)
      expect(sUSDbalanceBefore).to.be.equal(0)

      const synthToMint = await this.issuer.issuableSynthExpected(
        this.signers[1].address,
        COLLATERAL_CURRENCIES.ETH.currencyKey,
        ethers.utils.parseUnits("10"),
      )
      console.log("[synth to Mint check]", synthToMint.toString())
      const tx = await (
        await this.synthetix
          .connect(this.signers[1])
          .issueSynths(COLLATERAL_CURRENCIES.ETH.currencyKey, ethers.utils.parseUnits("10"), synthToMint, {
            from: this.signers[1].address,
            value: ethers.utils.parseUnits("10"),
          })
      ).wait()

      const sUSDbalanceAfter = await this.syUSDProxy.balanceOf(this.signers[1].address)
      expect(sUSDbalanceAfter).to.be.equal(synthToMint)

      const balanceAfter = await this.synthetix.balanceOf(this.signers[1].address)
      console.log("[synthetix balance check after]", balanceAfter.toString())
    })
    it("should do double minting Wrapped Synthr", async function () {
      const balanceBefore = await this.synthetix.balanceOf(this.signers[1].address)
      console.log("[synthetix balance check before]", balanceBefore.toString())

      const sUSDbalanceBefore = await this.syUSDProxy.balanceOf(this.signers[1].address)
      console.log("[sUSDbalanceBefore]", sUSDbalanceBefore.toString())

      const synthToMint = await this.issuer.issuableSynthExpected(
        this.signers[1].address,
        COLLATERAL_CURRENCIES.ETH.currencyKey,
        ethers.utils.parseUnits("10"),
      )
      console.log("[synth to Mint check]", synthToMint.toString())
      const tx = await (
        await this.synthetix
          .connect(this.signers[1])
          .issueSynths(COLLATERAL_CURRENCIES.ETH.currencyKey, ethers.utils.parseUnits("10"), synthToMint, {
            from: this.signers[1].address,
            value: ethers.utils.parseUnits("10"),
          })
      ).wait()
      // console.log('[issue transaction check]', await tx.wait())
      const sUSDbalanceAfter = await this.syUSDProxy.balanceOf(this.signers[1].address)
      expect(sUSDbalanceAfter).to.be.equal(sUSDbalanceBefore.add(synthToMint))

      const balanceAfter = await this.synthetix.balanceOf(this.signers[1].address)
      expect(balanceAfter).to.be.equal(balanceBefore.mul(2))

      const synthToMint2 = await this.issuer.issuableSynthExpected(
        this.signers[1].address,
        COLLATERAL_CURRENCIES.ETH.currencyKey,
        ethers.utils.parseUnits("5"),
      )
      console.log("[synth to Mint check 2]", synthToMint2.toString())

      const tx2 = await (
        await this.synthetix
          .connect(this.signers[1])
          .issueSynths(COLLATERAL_CURRENCIES.ETH.currencyKey, ethers.utils.parseUnits("5"), synthToMint2, {
            from: this.signers[1].address,
            value: ethers.utils.parseUnits("5"),
          })
      ).wait()
      // console.log('[issue transaction check]', await tx.wait())
      const sUSDbalanceAfter2 = await this.syUSDProxy.balanceOf(this.signers[1].address)
      expect(sUSDbalanceAfter2).to.be.equal(sUSDbalanceAfter.add(synthToMint2))

      const balanceAfter2 = await this.synthetix.balanceOf(this.signers[1].address)
      expect(balanceAfter2).to.be.equal(balanceBefore.mul(5).div(2))
    })
    it("should mint Wrapped Synthr but mint syAsset to half of the mintable amount", async function () {
      const balanceBefore = await this.synthetix.balanceOf(this.signers[1].address)
      console.log("[synthetix balance check before]", balanceBefore.toString())

      const sUSDbalanceBefore = await this.syUSDProxy.balanceOf(this.signers[1].address)
      console.log("[sUSDbalanceBefore]", sUSDbalanceBefore.toString())

      const synthToMint = await this.issuer.issuableSynthExpected(
        this.signers[1].address,
        COLLATERAL_CURRENCIES.ETH.currencyKey,
        ethers.utils.parseUnits("10"),
      )
      console.log("[synth to Mint check]", synthToMint.toString())
      const tx = await (
        await this.synthetix
          .connect(this.signers[1])
          .issueSynths(COLLATERAL_CURRENCIES.ETH.currencyKey, ethers.utils.parseUnits("10"), synthToMint.div(2), {
            from: this.signers[1].address,
            value: ethers.utils.parseUnits("10"),
          })
      ).wait()
      // console.log('[issue transaction check]', await tx.wait())
      const sUSDbalanceAfter = await this.syUSDProxy.balanceOf(this.signers[1].address)
      expect(sUSDbalanceAfter).to.be.equal(sUSDbalanceBefore.add(synthToMint.div(2)))

      const balanceAfter = await this.synthetix.balanceOf(this.signers[1].address)
      // (10ETH + 10ETH + 5ETH) + 10ETH = 25ETH + 10ETH => 
      expect(balanceAfter).to.be.equal(balanceBefore.mul(7).div(5))
    })
  })
  describe("Wrapped Synthr Burning Process", function () {
    it("should revert to burn Wrapped Synthr and withdraw Collateral for invalid request", async function () {
      const balanceBefore = await this.synthetix.balanceOf(this.signers[1].address)
      console.log("[synthetix balance check before burn]", balanceBefore.toString())

      const sUSDbalanceBefore = await this.syUSDProxy.balanceOf(this.signers[1].address)
      console.log("[syUSD balance before burn]", sUSDbalanceBefore.toString())

      const freeCollateralBefore = await this.issuer.checkFreeCollateral(this.signers[1].address, COLLATERAL_CURRENCIES.ETH.currencyKey)
      expect(freeCollateralBefore).to.be.equal(ethers.utils.parseUnits("5"))

      await expect(this.synthetix
          .connect(this.signers[1])
          .withdrawCollateral(COLLATERAL_CURRENCIES.ETH.currencyKey, ethers.utils.parseUnits("10"))
      ).to.be.revertedWith("Overflow free collateral.")

      const sUSDbalanceAfter = await this.syUSDProxy.balanceOf(this.signers[1].address)
      expect(sUSDbalanceBefore).to.be.equal(sUSDbalanceAfter)

      const balanceAfter = await this.synthetix.balanceOf(this.signers[1].address)
      expect(balanceBefore).to.be.equal(balanceAfter)

    })
    it("should burn Wrapped Synthr and withdraw Collateral", async function () {
      const balanceBefore = await this.synthetix.balanceOf(this.signers[1].address)

      const sUSDbalanceBefore = await this.syUSDProxy.balanceOf(this.signers[1].address)

      const synthToMint = await this.issuer.issuableSynthExpected(
        this.signers[1].address,
        COLLATERAL_CURRENCIES.ETH.currencyKey,
        ethers.utils.parseUnits("10"),
      )
      console.log("[synth to Mint check]", synthToMint.toString())

      const freeCollateralBefore = await this.issuer.checkFreeCollateral(this.signers[1].address, COLLATERAL_CURRENCIES.ETH.currencyKey)
      expect(freeCollateralBefore).to.be.equal(ethers.utils.parseUnits("5"))

      await (await this.synthetix
          .connect(this.signers[1])
          .withdrawCollateral(COLLATERAL_CURRENCIES.ETH.currencyKey, freeCollateralBefore)
      ).wait()

      const freeCollateralAfter = await this.issuer.checkFreeCollateral(this.signers[1].address, COLLATERAL_CURRENCIES.ETH.currencyKey)
      expect(freeCollateralAfter).to.be.equal(0)

      const sUSDbalanceAfter = await this.syUSDProxy.balanceOf(this.signers[1].address)
      expect(sUSDbalanceAfter).to.be.equal(sUSDbalanceBefore)

      const balanceAfter2 = await this.synthetix.balanceOf(this.signers[1].address)
      // 10 ETH + 10 ETH + 5ETH + 10 ETH - 5ETH => 35 ETH - 5 ETH = 30 ETH => 
      expect(balanceAfter2).to.be.equal(balanceBefore.mul(6).div(7))

    })
    it("should burn syAssets", async function () {
      const balanceBefore = await this.synthetix.balanceOf(this.signers[1].address)
      console.log('[synthetix balance check before burn]', balanceBefore.toString())
      const sUSDbalanceBefore = await this.syUSDProxy.balanceOf(this.signers[1].address)
      console.log('[syUSD balance check before burn]', sUSDbalanceBefore.toString())

      const remainingIssuableBefore = await this.synthetix.remainingIssuableSynths(this.signers[1].address)
      expect(remainingIssuableBefore.maxIssuable).to.be.equal(0)

      const tx2 = await (
        await this.synthetix
          .connect(this.signers[1])
          .burnSynths(sUSDbalanceBefore)
      ).wait()

      const sUSDbalanceAfter = await this.syUSDProxy.balanceOf(this.signers[1].address)
      expect(sUSDbalanceAfter).to.be.equal(0)

      const balanceAfter = await this.synthetix.balanceOf(this.signers[1].address)
      expect(balanceBefore).to.be.equal(balanceAfter)

      const remainingIssuableAfter = await this.synthetix.remainingIssuableSynths(this.signers[1].address)
      expect(remainingIssuableAfter.maxIssuable).to.be.equal(sUSDbalanceBefore)
    })
  })
})
