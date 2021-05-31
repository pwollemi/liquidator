const SwapRepayTool = artifacts.require("SwapRepayTool");

module.exports = async function (deployer, network, accounts) {
    await deployer.deploy(SwapRepayTool, 
        "0x" // _swapWrapper
        );

    console.log("***********************************************");
    console.log("SwapRepayTool address:", SwapRepayTool.address);
    console.log("***********************************************");
}
