// We require the Hardhat Runtime Environment explicitly here. This is optional 
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const { ethers } = require("ethers");
const hre = require("hardhat");

async function main() {
  // Hardhat always runs the compile task when running scripts with its command
  // line interface.
  //
  // If this script is run directly using `node` you may want to call compile 
  // manually to make sure everything is compiled
  // await hre.run('compile');

  const [operator] = await hre.ethers.getSigners();

  let a1 = "0xCA8d6F69D8f32516a109Df68B623452cc9f5E64d"
  const owner_signer = await hre.ethers.provider.getSigner(a1);
  await hre.network.provider.request({
    method: "hardhat_impersonateAccount",
    params: [a1]}
  )
  
  let mkr_address = "0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2"

  let mkr_token = await hre.ethers.getContractAt("ERC20",mkr_address);
    
  await mkr_token.connect(owner_signer).transfer(operator.address,10000000);

  const MKRVoteRewards = await hre.ethers.getContractFactory("MKRVoteRewards");
  const mkrVoteRewards = await MKRVoteRewards.deploy(mkr_address);
  await mkrVoteRewards.deployed();

  console.log("mkrVoteRewards deployed to:", mkrVoteRewards.address);

  await mkr_token.approve(mkrVoteRewards.address,10000000);

  await mkrVoteRewards.stake(10000000);
  await mkrVoteRewards.withdraw(1000);
  await mkrVoteRewards.withdraw(10000000-1000);

}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
