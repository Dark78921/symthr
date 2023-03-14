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
const SYNTHETIX_PROXY = require("./abis/synthetixProxy.json")

async function main() {
  const signers = await ethers.getSigners()
  // const Synthetix = await ethers.getContractFactory("Synthetix");
  // const synthetix = await Synthetix.attach(addressList.Synthetix);
  // console.log("[synthetix address]", synthetix.address);
  // tx = await synthetix.mint();
  // console.log('[synthetix mint]', await tx.wait())

  const synthetixProxy = new ethers.Contract(addressList.SynthetixProxy, SYNTHETIX_PROXY, signers[0])
  const tx = await (
    await synthetixProxy.transfer("0x87216b0Ae8e01CF2700fD928C43D0eD77aeA0307", ethers.utils.parseUnits("1000", 18))
  ).wait()

  console.log("[transfer tx check]", tx.transactionHash)
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
