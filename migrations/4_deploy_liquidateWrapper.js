const LiquidatorProxy = artifacts.require("LiquidatorProxy");
const LiquidateWrapper = artifacts.require("LiquidateWrapper");

module.exports = async function (deployer, network, accounts) {
    await deployer.deploy(LiquidateWrapper);
    await deployer.deploy(LiquidatorProxy, LiquidateWrapper.address);

    const instance = await LiquidateWrapper.at(LiquidatorProxy.address);
    // heco
    await instance.initialize(
        "0x", // _governance
        '0x', // _swapWrapper
        '0x' // _CEtherAddress
    );

    console.log("***********************************************");
    console.log("LiquidateWrapper address:", LiquidatorProxy.address);
    console.log("***********************************************");
};
