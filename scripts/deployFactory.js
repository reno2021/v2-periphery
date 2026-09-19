const hre = require('hardhat');
const { DEFAULT_ADMIN_WALLET, requireEnv } = require('./shared');

async function main() {
  const feeToSetter = requireEnv('FACTORY_FEE_TO_SETTER', DEFAULT_ADMIN_WALLET);
  const Factory = await hre.ethers.getContractFactory('UniswapV2Factory');
  const factory = await Factory.deploy(feeToSetter);
  await factory.waitForDeployment();
  console.log(JSON.stringify({
    chainId: 4663,
    feeToSetter,
    factory: await factory.getAddress()
  }, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
