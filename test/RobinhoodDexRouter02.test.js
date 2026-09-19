const { expect } = require('chai');
const { ethers } = require('hardhat');

const BPS = 10000n;
const PROTOCOL_FEE_BPS = 120n;
const CORE_SWAP_FEE_NUMERATOR = 997n;
const CORE_SWAP_FEE_DENOMINATOR = 1000n;
const ZERO_ADDRESS = ethers.ZeroAddress;

function feeFromGross(amount) {
  return (amount * PROTOCOL_FEE_BPS) / BPS;
}

function netFromGross(amount) {
  return amount - feeFromGross(amount);
}

function grossUp(net) {
  if (net === 0n) return 0n;
  return (net * BPS + (BPS - PROTOCOL_FEE_BPS) - 1n) / (BPS - PROTOCOL_FEE_BPS);
}

function getAmountOutPair(amountIn, reserveIn, reserveOut) {
  const amountInWithFee = amountIn * CORE_SWAP_FEE_NUMERATOR;
  return (amountInWithFee * reserveOut) / (reserveIn * CORE_SWAP_FEE_DENOMINATOR + amountInWithFee);
}

function getAmountInPair(amountOut, reserveIn, reserveOut) {
  return ((reserveIn * amountOut * CORE_SWAP_FEE_DENOMINATOR) / ((reserveOut - amountOut) * CORE_SWAP_FEE_NUMERATOR)) + 1n;
}

async function currentDeadline() {
  const block = await ethers.provider.getBlock('latest');
  return BigInt(block.timestamp + 3600);
}

async function deployFixture() {
  const [deployer, admin, alice, bob] = await ethers.getSigners();
  const Factory = await ethers.getContractFactory('UniswapV2Factory');
  const factory = await Factory.deploy(deployer.address);
  await factory.waitForDeployment();

  const WETH = await ethers.getContractFactory('WETH9');
  const weth = await WETH.deploy();
  await weth.waitForDeployment();

  const Router = await ethers.getContractFactory('RobinhoodDexRouter02');
  const router = await Router.deploy(await factory.getAddress(), await weth.getAddress(), admin.address);
  await router.waitForDeployment();

  const Token = await ethers.getContractFactory('ERC20TestToken');
  const supply = ethers.parseEther('1000000');
  const tokenA = await Token.deploy('Token A', 'TKA', supply);
  const tokenB = await Token.deploy('Token B', 'TKB', supply);
  await tokenA.waitForDeployment();
  await tokenB.waitForDeployment();

  for (const signer of [deployer, alice, bob]) {
    await tokenA.connect(deployer).mint(signer.address, ethers.parseEther('100000'));
    await tokenB.connect(deployer).mint(signer.address, ethers.parseEther('100000'));
    await tokenA.connect(signer).approve(await router.getAddress(), ethers.MaxUint256);
    await tokenB.connect(signer).approve(await router.getAddress(), ethers.MaxUint256);
  }

  return { deployer, admin, alice, bob, factory, weth, router, tokenA, tokenB };
}

describe('RobinhoodDexRouter02', function () {
  it('creates a pair during addLiquidity and sends the 1.2% fees to the admin wallet', async function () {
    const { admin, alice, factory, router, tokenA, tokenB } = await deployFixture();
    const grossA = ethers.parseEther('1000');
    const grossB = ethers.parseEther('500');
    const netA = netFromGross(grossA);
    const netB = netFromGross(grossB);
    const deadline = await currentDeadline();

    const adminTokenABefore = await tokenA.balanceOf(admin.address);
    const adminTokenBBefore = await tokenB.balanceOf(admin.address);

    const tx = await router
      .connect(alice)
      .addLiquidity(
        await tokenA.getAddress(),
        await tokenB.getAddress(),
        grossA,
        grossB,
        netA,
        netB,
        alice.address,
        deadline
      );
    const receipt = await tx.wait();
    expect(receipt.status).to.equal(1);

    const pairAddress = await factory.getPair(await tokenA.getAddress(), await tokenB.getAddress());
    expect(pairAddress).to.not.equal(ZERO_ADDRESS);

    const pair = await ethers.getContractAt(
      '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol:IUniswapV2Pair',
      pairAddress
    );
    const reserves = await pair.getReserves();
    expect(reserves[0]).to.equal(netA);
    expect(reserves[1]).to.equal(netB);
    expect(await tokenA.balanceOf(admin.address) - adminTokenABefore).to.equal(grossA - netA);
    expect(await tokenB.balanceOf(admin.address) - adminTokenBBefore).to.equal(grossB - netB);
  });

  it('quotes and collects swap fees consistently and preserves slippage protection', async function () {
    const { admin, alice, factory, router, tokenA, tokenB } = await deployFixture();
    const liquidityGross = ethers.parseEther('10000');
    const liquidityNet = netFromGross(liquidityGross);
    const deadline = await currentDeadline();

    await router
      .connect(alice)
      .addLiquidity(
        await tokenA.getAddress(),
        await tokenB.getAddress(),
        liquidityGross,
        liquidityGross,
        liquidityNet,
        liquidityNet,
        alice.address,
        deadline
      );

    const path = [await tokenA.getAddress(), await tokenB.getAddress()];
    const grossSwapIn = ethers.parseEther('100');
    const expectedPairInput = netFromGross(grossSwapIn);
    const expectedOut = getAmountOutPair(expectedPairInput, liquidityNet, liquidityNet);

    const quotedOut = await router.getAmountOut(grossSwapIn, liquidityNet, liquidityNet);
    expect(quotedOut).to.equal(expectedOut);

    const quotedPathOut = await router.getAmountsOut(grossSwapIn, path);
    expect(quotedPathOut[0]).to.equal(grossSwapIn);
    expect(quotedPathOut[1]).to.equal(expectedOut);

    let reverted = false;
    try {
      await router
        .connect(alice)
        .swapExactTokensForTokens(grossSwapIn, expectedOut + 1n, path, alice.address, deadline);
    } catch (error) {
      reverted = String(error).includes('RobinhoodDexRouter: INSUFFICIENT_OUTPUT_AMOUNT');
    }
    expect(reverted).to.equal(true);

    const adminTokenBefore = await tokenA.balanceOf(admin.address);
    const userTokenBefore = await tokenB.balanceOf(alice.address);
    const swapTx = await router
      .connect(alice)
      .swapExactTokensForTokens(grossSwapIn, expectedOut, path, alice.address, deadline);
    await swapTx.wait();

    expect(await tokenA.balanceOf(admin.address) - adminTokenBefore).to.equal(grossSwapIn - expectedPairInput);
    expect(await tokenB.balanceOf(alice.address) - userTokenBefore).to.equal(expectedOut);

    const quotedIn = await router.getAmountsIn(expectedOut, path);
    expect(quotedIn[0] >= grossSwapIn).to.equal(true);
    expect(quotedIn[1]).to.equal(expectedOut);

    const livePairAddress = await factory.getPair(await tokenA.getAddress(), await tokenB.getAddress());
    const pair = await ethers.getContractAt(
      '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol:IUniswapV2Pair',
      livePairAddress
    );
    const postSwapReserves = await pair.getReserves();
    const reserveInAfterFirstSwap = postSwapReserves[0];
    const reserveOutAfterFirstSwap = postSwapReserves[1];
    const pairInputForExactOut = getAmountInPair(expectedOut, reserveInAfterFirstSwap, reserveOutAfterFirstSwap);

    const adminTokenBeforeExactOut = await tokenA.balanceOf(admin.address);
    const userTokenABeforeExactOut = await tokenA.balanceOf(alice.address);
    const userTokenBBeforeExactOut = await tokenB.balanceOf(alice.address);
    await router
      .connect(alice)
      .swapTokensForExactTokens(expectedOut, quotedIn[0], path, alice.address, deadline);
    expect(await tokenA.balanceOf(admin.address) - adminTokenBeforeExactOut).to.equal(
      quotedIn[0] - pairInputForExactOut
    );
    expect(userTokenABeforeExactOut - (await tokenA.balanceOf(alice.address))).to.equal(quotedIn[0]);
    expect(await tokenB.balanceOf(alice.address) - userTokenBBeforeExactOut).to.equal(expectedOut);
  });

  it('charges protocol fees on addLiquidityETH and refunds unused ETH', async function () {
    const { admin, alice, router, factory, weth, tokenA } = await deployFixture();
    const grossToken = ethers.parseEther('1000');
    const grossETH = ethers.parseEther('10');
    const netToken = netFromGross(grossToken);
    const netETH = netFromGross(grossETH);
    const deadline = await currentDeadline();

    const adminEthBefore = await ethers.provider.getBalance(admin.address);
    const adminTokenBefore = await tokenA.balanceOf(admin.address);

    await router
      .connect(alice)
      .addLiquidityETH(await tokenA.getAddress(), grossToken, netToken, netETH, alice.address, deadline, {
        value: grossETH
      });

    const pairAddress = await factory.getPair(await tokenA.getAddress(), await weth.getAddress());
    const pair = await ethers.getContractAt(
      '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol:IUniswapV2Pair',
      pairAddress
    );
    const reserves = await pair.getReserves();
    const token0 = (await tokenA.getAddress()).toLowerCase() < (await weth.getAddress()).toLowerCase();
    const reserveToken = token0 ? reserves[0] : reserves[1];
    const reserveWeth = token0 ? reserves[1] : reserves[0];

    expect(reserveToken).to.equal(netToken);
    expect(reserveWeth).to.equal(netETH);
    expect(await tokenA.balanceOf(admin.address) - adminTokenBefore).to.equal(grossToken - netToken);
    expect(await ethers.provider.getBalance(admin.address) - adminEthBefore).to.equal(grossETH - netETH);
  });

  it('refunds excess ETH and scales token usage to the chosen ETH gross budget', async function () {
    const { admin, alice, bob, factory, router, tokenA, weth } = await deployFixture();
    const deadline = await currentDeadline();
    const initialGrossToken = ethers.parseEther('1000');
    const initialGrossETH = ethers.parseEther('10');
    const initialNetToken = netFromGross(initialGrossToken);
    const initialNetETH = netFromGross(initialGrossETH);

    await router
      .connect(alice)
      .addLiquidityETH(
        await tokenA.getAddress(),
        initialGrossToken,
        initialNetToken,
        initialNetETH,
        alice.address,
        deadline,
        { value: initialGrossETH }
      );

    const grossToken = ethers.parseEther('100');
    const extraEthValue = ethers.parseEther('5');
    const adminEthBefore = await ethers.provider.getBalance(admin.address);
    const bobEthBefore = await ethers.provider.getBalance(bob.address);
    const addTx = await router
      .connect(bob)
      .addLiquidityETH(await tokenA.getAddress(), grossToken, 0, 0, bob.address, deadline, { value: extraEthValue });
    const addReceipt = await addTx.wait();
    const addTransaction = await ethers.provider.getTransaction(addReceipt.hash);
    const gasPrice = addReceipt.gasPrice ?? addReceipt.effectiveGasPrice ?? addTransaction.gasPrice ?? addTransaction.maxFeePerGas;
    const gasCost = addReceipt.gasUsed * gasPrice;
    const bobEthAfter = await ethers.provider.getBalance(bob.address);
    const grossEthUsed = bobEthBefore - bobEthAfter - gasCost;
    const expectedNetToken = netFromGross(grossToken);
    const expectedNetETH = (expectedNetToken * initialNetETH) / initialNetToken;
    const expectedGrossEthUsed = grossUp(expectedNetETH);

    expect(grossEthUsed).to.equal(expectedGrossEthUsed);
    expect(await ethers.provider.getBalance(admin.address) - adminEthBefore).to.equal(feeFromGross(expectedGrossEthUsed));

    const pairAddress = await factory.getPair(await tokenA.getAddress(), await weth.getAddress());
    const pair = await ethers.getContractAt(
      '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol:IUniswapV2Pair',
      pairAddress
    );
    const reserves = await pair.getReserves();
    const token0 = (await tokenA.getAddress()).toLowerCase() < (await weth.getAddress()).toLowerCase();
    const reserveToken = token0 ? reserves[0] : reserves[1];
    const reserveWeth = token0 ? reserves[1] : reserves[0];
    const constrainedGrossETH = ethers.parseEther('1');
    const expectedGrossTokenUsed = (constrainedGrossETH * reserveToken) / reserveWeth;
    const adminTokenBefore = await tokenA.balanceOf(admin.address);
    const bobTokenBefore = await tokenA.balanceOf(bob.address);

    await router
      .connect(bob)
      .addLiquidityETH(await tokenA.getAddress(), ethers.parseEther('200'), 0, 0, bob.address, deadline, {
        value: constrainedGrossETH
      });

    expect(bobTokenBefore - (await tokenA.balanceOf(bob.address))).to.equal(expectedGrossTokenUsed);
    expect(await tokenA.balanceOf(admin.address) - adminTokenBefore).to.equal(feeFromGross(expectedGrossTokenUsed));
  });

  it('charges token and ETH fees when removing token/WETH liquidity', async function () {
    const { admin, alice, bob, router, factory, weth, tokenA } = await deployFixture();
    const grossToken = ethers.parseEther('1000');
    const grossETH = ethers.parseEther('10');
    const netToken = netFromGross(grossToken);
    const netETH = netFromGross(grossETH);
    const deadline = await currentDeadline();

    await router
      .connect(alice)
      .addLiquidityETH(await tokenA.getAddress(), grossToken, netToken, netETH, alice.address, deadline, {
        value: grossETH
      });

    const pairAddress = await factory.getPair(await tokenA.getAddress(), await weth.getAddress());
    const pair = await ethers.getContractAt(
      '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol:IUniswapV2Pair',
      pairAddress
    );

    const liquidity = (await pair.balanceOf(alice.address)) / 2n;
    await pair.connect(alice).approve(await router.getAddress(), liquidity);

    const reserves = await pair.getReserves();
    const totalSupply = await pair.totalSupply();
    const token0 = (await tokenA.getAddress()).toLowerCase() < (await weth.getAddress()).toLowerCase();
    const reserveToken = token0 ? reserves[0] : reserves[1];
    const reserveWeth = token0 ? reserves[1] : reserves[0];
    const grossTokenOut = (liquidity * reserveToken) / totalSupply;
    const grossEthOut = (liquidity * reserveWeth) / totalSupply;
    const expectedTokenToRecipient = grossTokenOut - feeFromGross(grossTokenOut);
    const expectedEthToRecipient = grossEthOut - feeFromGross(grossEthOut);

    const adminTokenBefore = await tokenA.balanceOf(admin.address);
    const adminEthBefore = await ethers.provider.getBalance(admin.address);
    const bobTokenBefore = await tokenA.balanceOf(bob.address);
    const bobEthBefore = await ethers.provider.getBalance(bob.address);

    const result = await router
      .connect(alice)
      .removeLiquidityETH.staticCall(
        await tokenA.getAddress(),
        liquidity,
        expectedTokenToRecipient,
        expectedEthToRecipient,
        bob.address,
        deadline
      );
    expect(result[0]).to.equal(expectedTokenToRecipient);
    expect(result[1]).to.equal(expectedEthToRecipient);

    const tx = await router
      .connect(alice)
      .removeLiquidityETH(
        await tokenA.getAddress(),
        liquidity,
        expectedTokenToRecipient,
        expectedEthToRecipient,
        bob.address,
        deadline
      );
    await tx.wait();

    expect(await tokenA.balanceOf(admin.address) - adminTokenBefore).to.equal(feeFromGross(grossTokenOut));
    expect(await ethers.provider.getBalance(admin.address) - adminEthBefore).to.equal(feeFromGross(grossEthOut));
    expect(await tokenA.balanceOf(bob.address) - bobTokenBefore).to.equal(expectedTokenToRecipient);
    expect(await ethers.provider.getBalance(bob.address) - bobEthBefore).to.equal(expectedEthToRecipient);
  });

  it('supports fee-on-transfer token swaps and rejects token-contract recipients', async function () {
    const { admin, alice, deployer, factory, router, tokenB } = await deployFixture();
    const FeeToken = await ethers.getContractFactory('FeeOnTransferToken');
    const feeToken = await FeeToken.deploy(
      'Fee Token',
      'FEE',
      ethers.parseEther('1000000'),
      100,
      deployer.address
    );
    await feeToken.waitForDeployment();
    await feeToken.connect(deployer).mint(alice.address, ethers.parseEther('10000'));
    await feeToken.connect(deployer).approve(await router.getAddress(), ethers.MaxUint256);
    await feeToken.connect(alice).approve(await router.getAddress(), ethers.MaxUint256);
    await tokenB.connect(deployer).approve(await router.getAddress(), ethers.MaxUint256);

    await factory.createPair(await feeToken.getAddress(), await tokenB.getAddress());
    const pairAddress = await factory.getPair(await feeToken.getAddress(), await tokenB.getAddress());
    const pair = await ethers.getContractAt(
      '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol:IUniswapV2Pair',
      pairAddress
    );

    await feeToken.connect(deployer).transfer(pairAddress, ethers.parseEther('10000'));
    await tokenB.connect(deployer).transfer(pairAddress, ethers.parseEther('10000'));
    await pair.connect(deployer).mint(alice.address);

    const deadline = await currentDeadline();
    const path = [await feeToken.getAddress(), await tokenB.getAddress()];
    let invalidRecipientReverted = false;
    try {
      await router
        .connect(alice)
        .swapExactTokensForTokensSupportingFeeOnTransferTokens(
          ethers.parseEther('10'),
          1n,
          path,
          pairAddress,
          deadline
        );
    } catch (error) {
      invalidRecipientReverted = String(error).includes('RobinhoodDexRouter: INVALID_TO');
    }
    expect(invalidRecipientReverted).to.equal(true);

    const adminBefore = await feeToken.balanceOf(admin.address);
    const aliceTokenBBefore = await tokenB.balanceOf(alice.address);
    await router
      .connect(alice)
      .swapExactTokensForTokensSupportingFeeOnTransferTokens(ethers.parseEther('10'), 1n, path, alice.address, deadline);

    expect(await feeToken.balanceOf(admin.address) - adminBefore > 0n).to.equal(true);
    expect(await tokenB.balanceOf(alice.address) - aliceTokenBBefore > 0n).to.equal(true);
  });
});
