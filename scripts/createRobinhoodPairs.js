const hre = require('hardhat');
const { DEFAULT_WETH, getPairTokens, requireEnv } = require('./shared');

async function main() {
  const factoryAddress = requireEnv('FACTORY_ADDRESS');
  const wethAddress = requireEnv('WETH_ADDRESS', DEFAULT_WETH);
  const Factory = await hre.ethers.getContractFactory('UniswapV2Factory');
  const factory = Factory.attach(factoryAddress);
  const tokens = getPairTokens();
  const created = [];

  for (const [name, token] of Object.entries(tokens)) {
    let pair = await factory.getPair(wethAddress, token);
    if (pair === hre.ethers.ZeroAddress) {
      const tx = await factory.createPair(wethAddress, token);
      await tx.wait();
      pair = await factory.getPair(wethAddress, token);
    }
    created.push({ name, token, weth: wethAddress, pair });
  }

  console.log(JSON.stringify(created, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
