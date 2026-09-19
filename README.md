# Robinhood Chain Dex & Stake Periphery

Periphery contracts and deployment scripts for a Robinhood Chain (`chainId=4663`) Uniswap V2-style router fork.

## Status and scope

- This repository implements the **DEX periphery/router** layer only.
- It forwards the full **1.2% protocol fee** for swaps, add-liquidity deposits, and remove-liquidity withdrawals to the configured admin wallet.
- The fee split is documented as:
  - **0.9%** rewards / buybacks / burns / raffles / staking support
  - **0.3%** development
- Both portions are forwarded **raw to the same admin wallet**: `0x9a32e27d1c0961487b64035ea10a4f1087d254bc` by default.
- **Staking lockups, early-withdraw penalties, and farm pool logic are not implemented in this repository**. They require separate staking contracts that consume the forwarded admin fees.
- No deployment to Robinhood mainnet is performed by this repository or its tests.

## Important warnings

- **Independently verify every address, token contract, token metadata entry, and explorer endpoint before any live deployment.**
- This repository makes **no claim of audit, production readiness, or live deployment status**.
- Blockscout URLs are intentionally **environment-configurable**. Do not assume a verified API endpoint unless you confirm it yourself.
- The quote math assumes a standard Uniswap V2 core swap fee of **0.30% inside the pair** (`997 / 1000`) plus the router-level **1.2% protocol fee on user-facing DEX entry points**.
- This router intentionally avoids hard-coding a pair init code hash; it resolves pair addresses through the factory so it can track a fee-enabled core fork without assuming upstream bytecode.

## Robinhood Chain defaults

- Network name: Robinhood Chain
- Chain ID: `4663`
- Default RPC URL: `https://rpc.mainnet.chain.robinhood.com`
- Wrapped native token: `0x0Bd7D308F8E1639FAb988df18A8011f41EAcAD73`
- Default admin wallet: `0x9a32e27d1c0961487b64035ea10a4f1087d254bc`

Requested WETH pairs:

- Saitama in Hood: `0x5ba31b25a1aa4b85d4402894602edd3f9c8e3d7a`
- Cash Cat: `0x020bfc650a365f8bb26819deaabf3e21291018b4`
- PONS: `0x39dbed3a2bd333467115de45665cc57f813c4571`
- Artificial Inu: `0x2e8c31162b855a2ffa90f6f8634643ad6f111e18`

## Fee behavior

### Swaps

- `swapExact*` entry points charge the 1.2% protocol fee from the **user input amount**.
- `swap*ForExact*` entry points compute the exact pair input needed, then gross it up so the user pays pair input + protocol fee without double-charging.
- Quote helpers (`getAmountOut`, `getAmountIn`, `getAmountsOut`, `getAmountsIn`) reflect that router-level fee model.
- For `*SupportingFeeOnTransferTokens` input paths, the router first receives the token, computes the protocol fee from the router-observed receipt amount, then forwards the remainder to the pair. This avoids mis-accounting when the input token itself taxes transfers.

### Add liquidity

- The protocol fee is taken from the user-provided token/ETH amounts before liquidity is deposited into the pair.
- `amountAMin`, `amountBMin`, `amountTokenMin`, and `amountETHMin` are interpreted as **net amounts that must reach the pair after the router fee**.
- Because both sides use the same protocol fee rate, the reserve ratio math remains unchanged.

### Remove liquidity

- Liquidity is burned to the router, the router withholds the 1.2% protocol fee on each output asset, then forwards the net amounts to the recipient.
- `amountAMin`, `amountBMin`, `amountTokenMin`, and `amountETHMin` are interpreted as **net recipient amounts after the protocol fee**.
- For `removeLiquidityETHSupportingFeeOnTransferTokens`, token minimum checks are performed against the recipient balance delta after the router sends the fee-on-transfer token. Admin receipts may still vary if the underlying token taxes transfers.

## TODOs / integration assumptions

- **Core fork coordination:** if the Robinhood core fork changes the pair swap fee away from `0.30%`, update `contracts/libraries/RobinhoodDexLibrary.sol` and re-run the quote tests.
- **Factory/pair interface parity:** this repo assumes the core fork still exposes the standard Uniswap V2 `factory`, `pair`, `mint`, `burn`, `swap`, `permit`, and reserve interfaces.
- **Staking layer:** lock periods, liquidity-sensitive reward rates, early-withdrawal penalties, and pool management must live in a dedicated staking/farm repository or follow-up PR.

## Install

```bash
npm install
```

## Build

```bash
npm run compile
```

## Test

```bash
npm test
```

## Environment variables

Only use environment variables; do not commit private keys or live secrets.

- `ROBINHOOD_RPC_URL` - defaults to `https://rpc.mainnet.chain.robinhood.com`
- `DEPLOYER_PRIVATE_KEY` - optional deployer key for `hardhat run --network robinhood ...`
- `BLOCKSCOUT_API_URL` - optional Blockscout API endpoint for verification
- `BLOCKSCOUT_BROWSER_URL` - optional Blockscout browser base URL for verification
- `BLOCKSCOUT_API_KEY` - optional verification key placeholder if your Blockscout instance expects one
- `ALLOW_ADDRESS_DEFAULTS=true` - optional opt-in if you explicitly want the scripts to fall back to the documented Robinhood defaults below
- `FACTORY_FEE_TO_SETTER` - factory fee setter for `scripts/deployFactory.js`
- `FACTORY_ADDRESS` - required for router deployment and pair-management scripts
- `WETH_ADDRESS` - required unless `ALLOW_ADDRESS_DEFAULTS=true`
- `ADMIN_WALLET` - required unless `ALLOW_ADDRESS_DEFAULTS=true`
- `SAITAMA_IN_HOOD_ADDRESS`
- `CASH_CAT_ADDRESS`
- `PONS_ADDRESS`
- `ARTIFICIAL_INU_ADDRESS`

## Deploy factory

```bash
FACTORY_FEE_TO_SETTER=0xYourSetter \
npx hardhat run scripts/deployFactory.js --network robinhood
```

## Deploy router

```bash
FACTORY_ADDRESS=0xFactory \
WETH_ADDRESS=0x0Bd7D308F8E1639FAb988df18A8011f41EAcAD73 \
ADMIN_WALLET=0x9a32e27d1c0961487b64035ea10a4f1087d254bc \
npx hardhat run scripts/deployRouter.js --network robinhood
```

## Create the four requested WETH pairs

```bash
FACTORY_ADDRESS=0xFactory \
WETH_ADDRESS=0x0Bd7D308F8E1639FAb988df18A8011f41EAcAD73 \
npx hardhat run scripts/createRobinhoodPairs.js --network robinhood
```

## Print resulting pair addresses

```bash
FACTORY_ADDRESS=0xFactory \
WETH_ADDRESS=0x0Bd7D308F8E1639FAb988df18A8011f41EAcAD73 \
npx hardhat run scripts/printRobinhoodPairs.js --network robinhood
```

## Verification notes

If your Blockscout instance exposes a verified API endpoint, set `BLOCKSCOUT_API_URL` and `BLOCKSCOUT_BROWSER_URL`, then use the normal Hardhat verify flow, for example:

```bash
BLOCKSCOUT_API_URL=https://your.blockscout.instance/api \
BLOCKSCOUT_BROWSER_URL=https://your.blockscout.instance \
npx hardhat verify --network robinhood <router-address> <factory-address> <weth-address> <admin-wallet>
```

Do not assume any explorer API URL until you have independently verified it.
