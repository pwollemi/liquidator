const LiquidatorProxy = artifacts.require("LiquidatorProxy");
const SwapWrapper = artifacts.require("SwapWrapper");

module.exports = async function (deployer, network, accounts) {
  await deployer.deploy(SwapWrapper);
  await deployer.deploy(LiquidatorProxy, SwapWrapper.address);

  const zeroAddr = "0x0000000000000000000000000000000000000000";
  const instance = await SwapWrapper.at(LiquidatorProxy.address);
  // heco
  await instance.initialize(
    "0x", // _governance
    '0x', // _factory
    '0x' // _router
  );

  console.log("***********************************************");
  console.log("SwapWrapper address:", LiquidatorProxy.address);
  console.log("***********************************************");
};
