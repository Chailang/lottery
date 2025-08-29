// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.30;
import {Script, console} from "forge-std/Script.sol";
import {HelperConfig,CodeConstants} from "./HelperConfig.s.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {LinkToken} from "../test/mocks/LinkToken.sol";
import {DevOpsTools} from "foundry-devops/src/DevOpsTools.sol";

contract CreateSubscription is Script {
    //你可以使用 vm.startBroadcast() 和 vm.stopBroadcast() 来模拟真实链上交易发送。

    function createSubscriptionUsingConfig() public returns (uint256, address) {
        HelperConfig helperConfig = new HelperConfig();
        address vrfCoordinatorV2_5 = helperConfig.getConfigByChainId(block.chainid).vrfCoordinatorV2_5; //当前链上 VRF Coordinator 合约地址。
        address account =  helperConfig.getConfigByChainId(block.chainid).account; //用于发起交易的账户。
        return createSubscription(vrfCoordinatorV2_5, account);
    }
    //实际创建订阅的函数
    function createSubscription(address vrfCoordinatorV2_5, address account)public returns (uint256, address) {
        console.log("Creating subscription on chainId: ", block.chainid);
        vm.startBroadcast(account);
        //调用 VRF Coordinator 合约的 createSubscription 方法创建一个新的订阅, 这里用了 VRFCoordinatorV2_5Mock，说明在本地或者测试链上运行时使用 mock 合约，不会真的收费。
        uint256 subId = VRFCoordinatorV2_5Mock(vrfCoordinatorV2_5).createSubscription();
        vm.stopBroadcast();
        console.log("Your subscription Id is: ", subId);
        console.log("Please update the subscriptionId in HelperConfig.s.sol");
        //
        return (subId, vrfCoordinatorV2_5);
    }
    function run() external returns (uint256, address) {
        return createSubscriptionUsingConfig();
    }
}

/**
 * 给 Chainlink VRF subscription 充值 LINK。
 * 它和你之前的 CreateSubscription 配合使用：
 * 如果订阅不存在，就先创建，然后再充值
 * 
    流程
    run() → fundSubscriptionUsingConfig()
    获取当前链配置：
    如果 subscription 不存在 → 调用 CreateSubscription 创建
    调用 fundSubscription() 充值：
    本地链 → 调用 Mock VRF Coordinator
    测试网/主网 → 调用 LinkToken.transferAndCall 充值真实 LINK
*/
contract FundSubscription is CodeConstants, Script {
     uint96 public constant FUND_AMOUNT = 3 ether; //充值金额，这里固定为 3 LINK（单位为 ether，即 10^18 wei）
     function run() external {
        fundSubscriptionUsingConfig();
    }
    function fundSubscriptionUsingConfig() public {
        HelperConfig helperConfig = new HelperConfig();
        uint256 subId = helperConfig.getConfig().subscriptionId;
        address vrfCoordinatorV2_5 = helperConfig.getConfig().vrfCoordinatorV2_5;
        address link = helperConfig.getConfig().link;
        address account = helperConfig.getConfig().account;
        if (subId == 0){ //1 检查是否已有订阅
            CreateSubscription createSubscription = new CreateSubscription(); //新建 CreateSubscription 实例
            (uint256 updatedSubId, address updatedVRFv2) = createSubscription.run(); //调用 run() 创建订阅
            subId = updatedSubId; //更新 subId 和 vrfCoordinatorV2_5
            vrfCoordinatorV2_5 = updatedVRFv2;
            console.log("New SubId Created! ", subId, "VRF Address: ", vrfCoordinatorV2_5);
        }
        fundSubscription(vrfCoordinatorV2_5,subId,link,account);
    }
    //实际充值
    function fundSubscription(address vrfCoordinatorV2_5, uint256 subId, address link, address account) public {
        console.log("Funding subscription: ", subId);
        console.log("Using vrfCoordinator: ", vrfCoordinatorV2_5);
        console.log("On ChainID: ", block.chainid);

        // 本地链（Anvil/Foundry）使用 Mock VRF Coordinator
        // 调用 fundSubscription(subId, FUND_AMOUNT) 直接充值 Mock LINK
        // 不需要真实 LINK
        if (block.chainid == LOCAL_CHAIN_ID) {
            vm.startBroadcast(account);
            VRFCoordinatorV2_5Mock(vrfCoordinatorV2_5).fundSubscription(subId, FUND_AMOUNT * 100);
            vm.stopBroadcast();
        } else {
            //真实 LINK：
            //transferAndCall 是 Chainlink VRF 指定的充值方式
            //发送 FUND_AMOUNT LINK 给 VRF Coordinator，同时通过 abi.encode(subId) 传递订阅 
            //ID账户必须持有足够 LINK 才能成功
            console.log(LinkToken(link).balanceOf(msg.sender));
            console.log(msg.sender);
            console.log(LinkToken(link).balanceOf(address(this)));
            console.log(address(this));
            vm.startBroadcast(account);
            LinkToken(link).transferAndCall(vrfCoordinatorV2_5, FUND_AMOUNT, abi.encode(subId));
            vm.stopBroadcast();
        }
    }
}
/**
 * LinkToken 是你自己在测试环境里模拟定义的（比如用 interface 或 mock），那为什么看起来它就像是“真实的”一样可以调用成功呢？
这里需要区分几个概念：
合约类型 vs 合约地址
LinkToken(link) 只是告诉编译器：link 这个地址上的合约，符合 LinkToken 这个接口（或合约定义）。
它本身不会创建真实的 LINK Token，只是告诉 Solidity “我可以调用这个合约的函数，按这个接口来调用”。
调用是否成功
如果 link 地址指向一个真实部署在链上的 LINK Token 合约（例如测试网或主网），调用就是真的转账了。
如果 link 是你在本地模拟环境里部署的 mock 合约，调用也是可以执行的，但只是模拟逻辑，并不会影响真实网络。

为什么你看起来像是真实的
这是 Solidity 的多态机制：只要地址上有符合接口的函数，调用就能通过编译器检查，执行时也会成功。
关键是你提供的 link 地址：它可能是一个 mock token 合约地址，所以“转账”是模拟的，但代码写法和真实合约一样。
✅ 总结：
LinkToken(link) 并不自动生成真实的 LINK Token
它只是把一个地址当成符合 LinkToken 接口的合约来调用。
如果你在本地用 mock 部署了合约，转账成功只是“本地模拟”，
如果部署在测试网或主网，并且 link 是真实 LINK Token 合约地址，
那么就是实际操作。
*/



//它是一个用于 给 VRF 订阅添加消费者合约 的脚本合约（Foundry 脚本风格）：
contract AddConsumer is Script {

    /**
     * 
    这个脚本的作用是：
    获取最新部署的 Raffle 合约。
    从配置中读取 VRF 订阅、协调器和账户。
    把 Raffle 合约添加为 VRF 订阅的消费者。
    可以在本地测试或真实链上自动广播交易。
    * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * 
    给指定的 VRF 订阅 (subId) 添加一个消费者合约 (contractToAddToVrf)
    参数说明：
    contractToAddToVrf：你希望让 VRF 提供随机数的合约。
    vrfCoordinator：VRF 协调器合约地址，真实链上是 Chainlink VRF 协调器，测试中可能是 VRFCoordinatorV2_5Mock。
    subId：VRF 订阅 ID。
    account：发送交易的账户。
     * */ 
    function addConsumer(address contractToAddToVrf, address vrfCoordinator, uint256 subId, address account) public {
        console.log("Adding consumer contract: ", contractToAddToVrf);
        console.log("Using vrfCoordinator: ", vrfCoordinator);
        console.log("On ChainID: ", block.chainid);
        vm.startBroadcast(account);
        VRFCoordinatorV2_5Mock(vrfCoordinator).addConsumer(subId, contractToAddToVrf);
        vm.stopBroadcast();
    }

    function addConsumerUsingConfig(address mostRecentlyDeployed) public {
        HelperConfig helperConfig = new HelperConfig();
        uint256 subId = helperConfig.getConfig().subscriptionId;
        address vrfCoordinatorV2_5 = helperConfig.getConfig().vrfCoordinatorV2_5;
        address account = helperConfig.getConfig().account;
        addConsumer(mostRecentlyDeployed, vrfCoordinatorV2_5, subId, account);
    }

    function run() external {
        //自动获取 最近部署的 Raffle 合约地址。
        address mostRecentlyDeployed = DevOpsTools.get_most_recent_deployment("Raffle", block.chainid);
        addConsumerUsingConfig(mostRecentlyDeployed);
    }
}