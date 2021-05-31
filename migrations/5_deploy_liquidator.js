const LiquidatorProxy = artifacts.require("LiquidatorProxy");
const Liquidator = artifacts.require("Liquidator");

module.exports = async function (deployer, network, accounts) {
    await deployer.deploy(Liquidator);
    await deployer.deploy(LiquidatorProxy, Liquidator.address);

    const instance = await Liquidator.at(LiquidatorProxy.address);
    // heco
    await instance.initialize(
        "0x", // _governance
        '0x', // _liquidateWrapper
        '0x', // _HUSD
        '0x' // _USDT
    );

    console.log("***********************************************");
    console.log("Liquidator address:", LiquidatorProxy.address);
    console.log("***********************************************");
};
