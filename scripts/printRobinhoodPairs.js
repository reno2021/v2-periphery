const hre = require('hardhat');
const { DEFAULT_WETH, getPairTokens, requireEnv } = require('./shared');

async function main() {
  const factoryAddress = requireEnv('FACTORY_ADDRESS');
  const wethAddress = requireEnv('WETH_ADDRESS', DEFAULT_WETH);
  const Factory = await hre.ethers.getContractFactory('UniswapV2Factory');
  const factory = Factory.attach(factoryAddress);
  const tokens = getPairTokens();
  const pairs = [];

  for (const [name, token] of Object.entries(tokens)) {
    pairs.push({
      name,
      token,
      weth: wethAddress,
      pair: await factory.getPair(wethAddress, token)
    });
  }

  console.log(JSON.stringify(pairs, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
