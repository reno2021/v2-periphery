require('dotenv').config();
require('@nomicfoundation/hardhat-ethers');
require('@nomicfoundation/hardhat-verify');

const { subtask } = require('hardhat/config');
const { TASK_COMPILE_SOLIDITY_GET_SOLC_BUILD } = require('hardhat/builtin-tasks/task-names');

const {
  ROBINHOOD_RPC_URL = 'https://rpc.mainnet.chain.robinhood.com',
  DEPLOYER_PRIVATE_KEY,
  BLOCKSCOUT_API_URL,
  BLOCKSCOUT_BROWSER_URL
} = process.env;

const robinhoodAccounts = DEPLOYER_PRIVATE_KEY ? [DEPLOYER_PRIVATE_KEY] : [];

const localSolcBuilds = {
  '0.5.16': {
    compilerPath: require.resolve('solc-0.5.16/soljson.js'),
    longVersion: require('solc-0.5.16/package.json').version
  },
  '0.6.12': {
    compilerPath: require.resolve('solc-0.6.12/soljson.js'),
    longVersion: require('solc-0.6.12/package.json').version
  }
};

subtask(TASK_COMPILE_SOLIDITY_GET_SOLC_BUILD, async (args, _hre, runSuper) => {
  const build = localSolcBuilds[args.solcVersion];
  if (build) {
    return {
      version: args.solcVersion,
      longVersion: build.longVersion,
      compilerPath: build.compilerPath,
      isSolcJs: true
    };
  }
  return runSuper();
});

module.exports = {
  solidity: {
    compilers: [
      { version: '0.5.16', settings: { optimizer: { enabled: true, runs: 200 } } },
      { version: '0.6.12', settings: { optimizer: { enabled: true, runs: 200 } } }
    ]
  },
  networks: {
    hardhat: {},
    robinhood: {
      url: ROBINHOOD_RPC_URL,
      chainId: 4663,
      accounts: robinhoodAccounts
    }
  },
  etherscan: {
    apiKey: {
      robinhood: process.env.BLOCKSCOUT_API_KEY || 'verify-via-blockscout'
    },
    customChains: BLOCKSCOUT_API_URL && BLOCKSCOUT_BROWSER_URL ? [
      {
        network: 'robinhood',
        chainId: 4663,
        urls: {
          apiURL: BLOCKSCOUT_API_URL,
          browserURL: BLOCKSCOUT_BROWSER_URL
        }
      }
    ] : []
  }
};
