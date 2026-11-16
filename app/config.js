// JozzyPay deployment config — edit after the live Aevum deployment.
// The address below is the deterministic address from the local fork demo
// (demo/fork-demo.sh). Replace it with the real deployment address and the
// UI will use it. The UI also lets you paste any contract address by hand.
window.JOZZYPAY_CONFIG = {
  chainId: 44005,
  chainName: "QDay Aevum",
  rpcUrl: "https://rpc-test.qday.info",
  explorer: "https://explorer-test.qday.info",
  tokenAddress: "0x456569838f1d43009A91ebA4263147Afd7233483", // tUSD8, 6 decimals
  tokenSymbol: "tUSD8",
  tokenDecimals: 6,
  contractAddress: "0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9", // fork demo address — replace after live deploy
};
