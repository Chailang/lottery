// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.20;
import {Script,console2} from "forge-std/Script.sol";
import {Raffle} from "../src/Raffle.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {CreateSubscription,FundSubscription,AddConsumer} from "./Interactions.s.sol";
contract DeployRaffle is Script{
    function run() external{
        vm.startBroadcast();
        vm.stopBroadcast(); 
    }

    function deployContract() public returns (Raffle,HelperConfig){
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory networkConfig = helperConfig.getConfig();
        console2.log("network config:",networkConfig.vrfCoordinatorV2_5);
        if (networkConfig.subscriptionId == 0){ //没有订阅
          CreateSubscription createSub= new CreateSubscription(); //创建订阅
          (networkConfig.subscriptionId,networkConfig.vrfCoordinatorV2_5) = createSub.createSubscription(networkConfig.vrfCoordinatorV2_5,networkConfig.account);
          FundSubscription funder =  new FundSubscription();
          funder.fundSubscription(networkConfig.vrfCoordinatorV2_5,networkConfig.subscriptionId,networkConfig.link,networkConfig.account);  
           helperConfig.setConfig(block.chainid, networkConfig);
        }
        //部署合约
        vm.startBroadcast();
        Raffle raffle = new Raffle(
            networkConfig.entranceFee,
            networkConfig.interval,
            networkConfig.vrfCoordinatorV2_5,
            networkConfig.gasLane,
            networkConfig.subscriptionId,
            networkConfig.callbackGasLimit
        );
        vm.stopBroadcast();
        console2.log("Raffle deployed to:",address(raffle));

        ///自动添加消费者
        AddConsumer addConsumer = new AddConsumer();
        addConsumer.addConsumer(address(raffle),networkConfig.vrfCoordinatorV2_5,networkConfig.subscriptionId,networkConfig.account);

        return (raffle,helperConfig);
    }

}  