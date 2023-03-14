// Defining bytecode and abi from original contract on mainnet to ensure bytecode matches and it produces the same pair code hash

module.exports = async function ({ ethers, getNamedAccounts, deployments, getChainId }) {
  const { deploy } = deployments
  const { deployer } = await getNamedAccounts()
  const owner = deployer

  const addressManager = await deployments.get("Lib_AddressManager")


  await deploy("Lib_ResolvedDelegateProxy", {
    from: deployer,
    args: [addressManager.address, "OVM_L1CrossDomainMessenger"],
    log: true,
    deterministicDeployment: false,
  })
}

module.exports.tags = ["Lib_ResolvedDelegateProxy", "Synthetix"]
