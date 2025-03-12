require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

const config = {
  solidity: {
    version: "0.8.28",
    settings: {
      optimizer: {
        enabled: true,
        runs: 500,
      },
    },
  },
  evmVersion: "istanbul",
  networks: {
    bscTestnet: {
      url: process.env.RPC_BNB,
      accounts: [process.env.PRIVATE_KEY].filter(Boolean)
    },
    hadera: {
      url: process.env.RPC_HADERA,
      accounts: [process.env.PRIVATE_KEY].filter(Boolean)
    },
    "haqq-testedge2": {
      url : process.env.RPC_HAQQ,
      accounts: [process.env.PRIVATE_KEY].filter(Boolean)
    }
  },
  etherscan: {
    apiKey: {
      'haqq-testedge2': 'empty'
    },
    customChains: [
      {
        network: "haqq-testedge2",
        chainId: 54211,
        urls: {
          apiURL: "https://explorer.testedge2.haqq.network/api",
          browserURL: "https://explorer.testedge2.haqq.network"
        }
      }
    ]
  }
};

module.exports = config;