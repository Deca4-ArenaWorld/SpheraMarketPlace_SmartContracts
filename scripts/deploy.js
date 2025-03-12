const hre = require("hardhat");

async function main() {
  const baseURI = "https://example.com/api/token/";

  // Deploy SpheraNFT
  const SpheraNFT = await hre.ethers.getContractFactory("SpheraNFTCollection");
  const spheraNFT = await SpheraNFT.deploy("Sphera", "SP");
  await spheraNFT.waitForDeployment();
  console.log("SpheraNFT deployed to:", spheraNFT.target);

  // Deploy SpheraMarketplace
  const SpheraMarketplace = await hre.ethers.getContractFactory("NFTMarketplace");
  const spheraMarketplace = await SpheraMarketplace.deploy();
  await spheraMarketplace.waitForDeployment();
  console.log("SpheraMarketplace deployed to:", spheraMarketplace.target);

  // Deploy SpheraToken
  const SpheraToken = await hre.ethers.getContractFactory("SpheraToken");
  const _supply = '100000000000000000000000'
  const spheraToken = await SpheraToken.deploy("SpheraToken", "SPT", _supply);
  await spheraToken.waitForDeployment();;
  console.log("SpheraToken deployed to:", spheraToken.target);

  // Deploy sPoint contract
  const SPoint = await hre.ethers.getContractFactory("SpheraPoints");
  const sPoint = await SPoint.deploy("SpheraPoint", "SPoint");
  await sPoint.waitForDeployment();
  console.log("SPoint deployed to:", sPoint.target);

  console.log("Deployment and registration complete!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
