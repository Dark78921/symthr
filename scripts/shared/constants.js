const WETH_ADDRESS = {
  rinkeby: "0xc778417E063141139Fce010982780140Aa0cD5Ab", // this is WETH address in Uniswap router 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D on rinkeby
}

const UNISWAP_FACTORY_ADDRESS = {
  rinkeby: "0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f",
}

const UNISWAP_ROUTER_ADDRESS = {
  rinkeby: "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D",
}

const TWAP_ORACLE_PRICE_FEED_FACTORY = {
  rinkeby: "0x6fa8a7E5c13E4094fD4Fa288ba59544791E4c9d3",
}

const UNO = {
  rinkeby: "0x53fb43BaE4C13d6AFAD37fB37c3fC49f3Af433F5",
}

const USDT = {
  rinkeby: "0x40c035016AD732b6cFce34c3F881040B6C6cf71E",
}

const USDC = {
  rinkeby: "0xeb8f08a975Ab53E34D8a0330E0D34de942C95926",
}

const AGGREGATOR = {
  sEUR: "0x78F9e60608bF48a1155b4B2A5e31F32318a1d85F",
  sETH: "0x8A753747A1Fa494EC906cE90E9f37563A8AF630e",
}

const DEBTAGGREGATOR = {
  mainnet: "0x0981af0C002345c9C5AD5efd26242D0cBe5aCA99",
  rinkeby: "0x2865d646f82B6b343dB86c690d074d618C6f468b",
}

const SNXAGGREGATOR = {
  mainnet: "0xDC3EA94CD0AC27d9A86C180091e7f78C683d3699",
  rinkeby: "0xD3e3bC001cbac80e6cbf765B8FAB5648aDA7DE7e",
}

const UNO_USDT_PRICE_FEED = {
  rinkeby: "0x8EAD48786e0F1569625f95b650a5aC63222b9bF2",
}

const CURRENCY_KEYS = {
  sUSD: "0x7355534400000000000000000000000000000000000000000000000000000000",
  sEUR: "0x7345555200000000000000000000000000000000000000000000000000000000",
  sETH: "0x7345544800000000000000000000000000000000000000000000000000000000",
  SNX: "0x534e580000000000000000000000000000000000000000000000000000000000",
}

const COLLATERAL_CURRENCIES = {
  ETH: {
    currencyKey: "0x4554480000000000000000000000000000000000000000000000000000000000",
    currencyAddress: "0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6",
    aggregator: {
      goerli: "0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e",
    },
  },
  USDT: {
    currencyKey: "0x5553445400000000000000000000000000000000000000000000000000000000",
    currencyAddress: "0x509Ee0d083DdF8AC028f2a56731412edD63223B9",
  },
}

const Lib_ResolvedDelegateProxy = {
  mainnet: "",
  goerli: "0x39D5002B6240ff7c943F74FCD35b4AB29dD68F51",
}

// "ProxysETH": {
//   "bytes": "0x50726f7879734554480000000000000000000000000000000000000000000000",
//   "block": 11245818,
//   "contractName": "ProxyERC20sETH"
// },
// "TokenStatesETH": {
//   "bytes": "",
//   "block": 11245821,
//   "contractName": "TokenStatesETH"
// },
// "ProxysEUR": {
//   "bytes": "0x50726f7879734555520000000000000000000000000000000000000000000000",
//   "block": 11245829,
//   "contractName": "ProxyERC20sEUR"
// },
// "TokenStatesEUR": {
//   "bytes": "",
//   "block": 11245832,
//   "contractName": "TokenStatesEUR"
// },
// "SynthsETH": {
//   "bytes": "0x53796e7468734554480000000000000000000000000000000000000000000000",
//   "block": 11245824,
//   "contractName": "SynthsETH"
// },
// "SynthsBTC": {
//   "bytes": "0x53796e74687342544300000000000000000000000000000000000000000000",
//   "block": 11292794,
//   "contractName": "SynthsBTC"
// },
// "SynthsEUR": {
//   "bytes": "0x53796e7468734555520000000000000000000000000000000000000000000000",
//   "block": 11245835,
//   "contractName": "SynthsEUR"
// },
// "ProxyERC20sBTC": {
//   "bytes": "",
//   "block": 11292788,
//   "contractName": "ProxyERC20sBTC"
// },
// "TokenStatesBTC": {
//   "bytes": "",
//   "block": 11292791,
//   "contractName": "TokenStatesBTC"
// },
// "SNXAggregator": {
//   "bytes": "",
//   "block": 11263888,
//   "contractName": "SNXAggregator"
// },
// "EscrowChecker": {
//   "bytes": "0x457363726f77436865636b657200000000000000000000000000000000000000",
//   "block": 11274422,
//   "contractName": "EscrowChecker"
// },
// "CollateralErc20": {
//   "bytes": "0x436f6c6c61746572616c45726332300000000000000000000000000000000000",
//   "block": 11292828,
//   "contractName": "CollateralErc20"
// },
// "CollateralEth": {
//   "bytes": "0x436f6c6c61746572616c45746800000000000000000000000000000000000000",
//   "block": 11292831,
//   "contractName": "CollateralEth"
// },
// "CollateralUtil": {
//   "bytes": "0x436f6c6c61746572616c5574696c000000000000000000000000000000000000",
//   "block": 11292858,
//   "contractName": "CollateralUtil"
// },
// "SynthetixState": {
//   "bytes": "",
//   "block": 11351545,
//   "contractName": "SynthetixState"
// },
// "IssuanceEternalStorage": {
//   "bytes": "",
//   "block": 11367638,
//   "contractName": "IssuanceEternalStorage"
// },
// "ReadProxyAddressResolver": {
//   "bytes": "",
//   "block": 11367830,
//   "contractName": "ReadProxyAddressResolver"
// },
// "Math": {
//   "bytes": "",
//   "block": 11367841,
//   "contractName": "Math"
// },
// "StakingRewardsSNXBalancer": {
//   "bytes": "",
//   "block": 11351545,
//   "contractName": "StakingRewardsSNXBalancer"
// },
// "CollateralShort": {
//   "bytes": "0x436f6c6c61746572616c53686f72740000000000000000000000000000000000",
//   "block": 11368136,
//   "contractName": "CollateralShort"
// },
// "ShortingRewardssETH": {
//   "bytes": "",
//   "block": 11368232,
//   "contractName": "ShortingRewardssETH"
// },
// "ShortingRewardssBTC": {
//   "bytes": "",
//   "block": 11368235,
//   "contractName": "ShortingRewardssBTC"
// },
// "NativeEtherWrapper": {
//   "bytes": "0x4e61746976654574686572577261707065720000000000000000000000000000",
//   "block": 11368290,
//   "contractName": "NativeEtherWrapper"
// },
// "ProxysDASH": {
//   "bytes": "",
//   "block": 11247382,
//   "contractName": "ProxysDASH"
// },

module.exports = {
  WETH_ADDRESS,
  UNISWAP_FACTORY_ADDRESS,
  UNISWAP_ROUTER_ADDRESS,
  TWAP_ORACLE_PRICE_FEED_FACTORY,
  UNO,
  USDT,
  USDC,
  UNO_USDT_PRICE_FEED,
  AGGREGATOR,
  CURRENCY_KEYS,
  Lib_ResolvedDelegateProxy,
  COLLATERAL_CURRENCIES,
}
