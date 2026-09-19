const hre = require('hardhat');
const { DEFAULT_ADMIN_WALLET, DEFAULT_WETH, requireDeployerKeyForNetwork, requireEnv } = require('./shared');

async function main() {
  requireDeployerKeyForNetwork(hre);
  const factory = requireEnv('FACTORY_ADDRESS');
  const weth = requireEnv('WETH_ADDRESS', DEFAULT_WETH);
  const adminWallet = requireEnv('ADMIN_WALLET', DEFAULT_ADMIN_WALLET);
  const Router = await hre.ethers.getContractFactory('RobinhoodDexRouter02');
  const router = await Router.deploy(factory, weth, adminWallet);
  await router.waitForDeployment();
  console.log(JSON.stringify({
    chainId: 4663,
    factory,
    weth,
    adminWallet,
    router: await router.getAddress(),
    protocolFeeBps: 120,
    feeSplitBps: {
      rewardsBuybacksBurnsRaffles: 90,
      development: 30
    }
  }, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
