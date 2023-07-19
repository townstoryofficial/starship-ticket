async function main() {
    const [deployer] = await ethers.getSigners();
    const beginBalance = await deployer.getBalance();
  
    console.log("Deployer:", deployer.address);
    console.log("Balance:", ethers.utils.formatEther(beginBalance));

    // Deploy
    const startId = 1000000;
    const saleStartTime = 1687003200;
    const serverRole = "";
    
    const arbToken = "0x912CE59144191C1204E64559FE8253a0e49E6548";
    const passFactory = await ethers.getContractFactory("StarshipTicket");
    const passContract = await passFactory.deploy("StarshipTicket", "ST", startId, saleStartTime, serverRole, arbToken);
    console.log("GamePass Contract: ", passContract.address);

    // +++
    const endBalance = await deployer.getBalance();
    const gasSpend = beginBalance.sub(endBalance);

    console.log("\nLatest balance:", ethers.utils.formatEther(endBalance));
    console.log("Gas:", ethers.utils.formatEther(gasSpend));
  }

  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });