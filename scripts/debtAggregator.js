const { ethers, network } = require("hardhat")
const { BigNumber } = ethers
const {
  getBigNumber,
  getNumber,
  getHexStrFromStr,
  getPaddedHexStrFromBN,
  getChainId,
  getSignatureParameters,
  getPaddedHexStrFromBNArray,
} = require("./shared/utilities")
const addressList = require("./shared/rinkeby.json")
const DEBTAGGREGATOR_ABI = require("./abis/debtAggregator.json")

async function main() {
  const d = new Date()
  const currentTime = Math.floor(d.getTime() / 1000)
  console.log("[current time]", currentTime)
  const signers = await ethers.getSigners()
  const debtAggregator = new ethers.Contract(addressList.DebtRatioAggregator, DEBTAGGREGATOR_ABI, signers[0])
  console.log("[debtAggregator check]", debtAggregator.address)

  const tx1 = await (await debtAggregator.setAnswer(ethers.utils.parseUnits("1259936594381933626242374099", 0))).wait()
  console.log("[transaction check]", tx1.transactionHash)

  const tx2 = await (await debtAggregator.setAnsweredInRound(ethers.utils.parseUnits("18446744073709556128", 0))).wait()
  console.log("[transaction check]", tx2.transactionHash)

  const tx3 = await (await debtAggregator.setRoundId(ethers.utils.parseUnits("18446744073709556128", 0))).wait()
  console.log("[transaction check]", tx3.transactionHash)

  const tx4 = await (await debtAggregator.setUpdatedAt(currentTime)).wait()
  console.log("[transaction check]", tx4.transactionHash)

  const issuedSynthAggregator = new ethers.Contract(addressList.IssuedSynthsAggregator, DEBTAGGREGATOR_ABI, signers[0])
  console.log("[issuedSynthAggregator check]", issuedSynthAggregator.address)

  const tx5 = await (await issuedSynthAggregator.setUpdatedAt(currentTime)).wait()
  console.log("[transaction check]", tx5.transactionHash)

  const SNXAggregator = new ethers.Contract(addressList.SNXAggregator, DEBTAGGREGATOR_ABI, signers[0])
  console.log("[SNXAggregator check]", SNXAggregator.address)

  const tx6 = await (await SNXAggregator.setAnswer(ethers.utils.parseUnits("298500000", 0))).wait()
  console.log("[transaction check]", tx6.transactionHash)

  const tx7 = await (await SNXAggregator.setAnsweredInRound(ethers.utils.parseUnits("55340232221128671315", 0))).wait()
  console.log("[transaction check]", tx7.transactionHash)

  const tx8 = await (await SNXAggregator.setRoundId(ethers.utils.parseUnits("55340232221128671315", 0))).wait()
  console.log("[transaction check]", tx8.transactionHash)

  const tx9 = await (await SNXAggregator.setUpdatedAt(currentTime)).wait()
  console.log("[transaction check]", tx9.transactionHash)

  // const tx5 = await debtAggregator.setDecimals(ethers.utils.parseUnits("27", 0))
  // console.log('[transaction 5 check]', await tx5.wait());
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
