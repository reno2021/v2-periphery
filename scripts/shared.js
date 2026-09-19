const DEFAULT_ADMIN_WALLET = '0x9a32e27d1c0961487b64035ea10a4f1087d254bc';
const DEFAULT_WETH = '0x0Bd7D308F8E1639FAb988df18A8011f41EAcAD73';
const DEFAULT_PAIR_TOKENS = {
  saitamaInHood: '0x5ba31b25a1aa4b85d4402894602edd3f9c8e3d7a',
  cashCat: '0x020bfc650a365f8bb26819deaabf3e21291018b4',
  pons: '0x39dbed3a2bd333467115de45665cc57f813c4571',
  artificialInu: '0x2e8c31162b855a2ffa90f6f8634643ad6f111e18'
};
const allowAddressDefaults = process.env.ALLOW_ADDRESS_DEFAULTS === 'true';

function requireEnv(name, fallback) {
  const explicitValue = process.env[name];
  if (explicitValue) {
    return explicitValue;
  }
  if (allowAddressDefaults && fallback) {
    return fallback;
  }
  throw new Error(
    `Missing required environment variable: ${name}. Set ALLOW_ADDRESS_DEFAULTS=true to opt into the documented defaults.`
  );
}

function getPairTokens() {
  return {
    saitamaInHood: requireEnv('SAITAMA_IN_HOOD_ADDRESS', DEFAULT_PAIR_TOKENS.saitamaInHood),
    cashCat: requireEnv('CASH_CAT_ADDRESS', DEFAULT_PAIR_TOKENS.cashCat),
    pons: requireEnv('PONS_ADDRESS', DEFAULT_PAIR_TOKENS.pons),
    artificialInu: requireEnv('ARTIFICIAL_INU_ADDRESS', DEFAULT_PAIR_TOKENS.artificialInu)
  };
}

function requireDeployerKeyForNetwork(hre) {
  if (hre.network.name === 'robinhood' && !process.env.DEPLOYER_PRIVATE_KEY) {
    throw new Error('DEPLOYER_PRIVATE_KEY is required for robinhood network runs.');
  }
}

module.exports = {
  DEFAULT_ADMIN_WALLET,
  DEFAULT_WETH,
  DEFAULT_PAIR_TOKENS,
  getPairTokens,
  requireDeployerKeyForNetwork,
  requireEnv
};
