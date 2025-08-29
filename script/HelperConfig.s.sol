 // SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.20;
import {Script,console2} from "forge-std/Script.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {LinkToken} from "../test/mocks/LinkToken.sol";
/**
 * HelperConfig 的作用：
 * 统一管理不同链的 VRF、LINK、账户等配置
 * 自动判断本地链、测试网或主网，返回对应配置
 * 本地链会自动部署 Mock VRF 合约并创建 subscription
 * 脚本在创建 subscription 或者调用 VRF 时直接引用 getConfig() 即可，不需要手动修改地址
*/
abstract contract CodeConstants {
    //VRF 模拟需要的常量
    uint96 public constant MOCK_BASE_FEE = 0.25 ether; //模拟基础费
    uint96 public constant MOCK_GAS_PRICE_LINK = 1e9; //模拟每单位gas的LINK价格
    // LINK / ETH price
    int256 public constant MOCK_WEI_PER_UINT_LINK = 4e15;// 0.004 ETH per LINK

    address public constant FOUNDRY_DEFAULT_SENDER = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;

    // Chain IDs
    uint256 public constant ETH_SEPOLIA_CHAIN_ID = 11155111;
    uint256 public constant ETH_MAINNET_CHAIN_ID = 1;
    uint256 public constant LOCAL_CHAIN_ID = 31337;
}
contract HelperConfig is Script,CodeConstants {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error HelperConfig__InvalidChainId();  
     /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/ 
     struct NetworkConfig {
        uint256 entranceFee; //示例项目的入场费
        uint256 interval; //Chainlink Automation（Keepers）更新间隔
        address vrfCoordinatorV2_5; //VRF Coordinator 地址
        bytes32 gasLane; //VRF key hash，用于选择不同的 gas 价格策略
        uint256 subscriptionId;  //VRF subscription ID
        uint32 callbackGasLimit; //VRF 回调的 gas 限制
        address link; //LINK 代币地址
        address account; //用于发送交易的账户
    }
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    
    mapping (uint256 chainId => NetworkConfig) public networkConfigMapping;
    NetworkConfig public localNetworkConfig;

    /*//////////////////////////////////////////////////////////////
                               function
    //////////////////////////////////////////////////////////////*/
    constructor() {
        networkConfigMapping[ETH_SEPOLIA_CHAIN_ID] = getSepoliaEthConfig();
        networkConfigMapping[ETH_MAINNET_CHAIN_ID] = getSepoliaEthConfig();
    }

    function getConfig() public returns (NetworkConfig memory) {
        console2.log("block.chainid: %s", block.chainid);
        return getConfigByChainId(block.chainid);
    }
    function setConfig(
        uint256 chainId,
        NetworkConfig memory networkConfig
    ) public {
        networkConfigMapping[chainId] = networkConfig;
    }
    
    function getConfigByChainId(uint256 chainId) public returns (NetworkConfig memory) {
        if (networkConfigMapping[chainId].vrfCoordinatorV2_5 != address(0)) {
            return networkConfigMapping[chainId];
        } else if (chainId == LOCAL_CHAIN_ID) {
            return getOrCreateAnvilEthConfig();
        } else {
            revert HelperConfig__InvalidChainId();
        }
    }
    //sepolia测试链
    function getSepoliaEthConfig() public pure returns (NetworkConfig memory) {
        return
            NetworkConfig({
                entranceFee: 0.01 ether, // 0.01 ETH
                interval: 30, // 30 seconds
                vrfCoordinatorV2_5: 0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B,
                gasLane: 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae,
                subscriptionId: 0, // update this with your subscriptionId
                callbackGasLimit: 500000,
                link: 0x779877A7B0D9E8603169DdbD7836e478b4624789,
                account: 0xbc4b0Fc8eB6c564488c6Cb8859c09e37f839E441 //你自己控制的测试钱包地址 用来发交易、创建 VRF subscription、支付 LINK
            }); 
    }
    //sepolia测试链
    function getMainEthConfig() public pure returns (NetworkConfig memory) {
        return
            NetworkConfig({
                entranceFee: 0.01 ether, // 0.01 ETH
                interval: 30, // 30 seconds
                vrfCoordinatorV2_5: 0xD7f86b4b8Cae7D942340FF628F82735b7a20893a,
                gasLane: 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae,
                subscriptionId: 0, // update this with your subscriptionId
                callbackGasLimit: 500000,
                link:0x514910771AF9Ca656af840dff83E8264EcF986CA,
                account: 0xbc4b0Fc8eB6c564488c6Cb8859c09e37f839E441//你自己控制的真实钱包地址 用来发交易、创建 VRF subscription、支付 LINK
            }); 
    }

    
    //本地模拟链
    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        if (localNetworkConfig.vrfCoordinatorV2_5 != address(0)) {
            return localNetworkConfig;
        }
        //deployCode VRFCoordinatorV2_5Mock
        vm.startBroadcast();
        VRFCoordinatorV2_5Mock vrfCoordinatorV2_5Mock = new VRFCoordinatorV2_5Mock(
            MOCK_BASE_FEE,
            MOCK_GAS_PRICE_LINK,
            MOCK_WEI_PER_UINT_LINK
        );
        console2.log(unicode"⚠️ You have deployed a mock conract!");
        console2.log("Make sure this was intentional");
        console2.log("VRFCoordinatorV2_5Mock address=>%s",address(vrfCoordinatorV2_5Mock));
        LinkToken link = new LinkToken();
        uint256 subscriptionId = vrfCoordinatorV2_5Mock.createSubscription();
        vm.stopBroadcast();
        localNetworkConfig = NetworkConfig({
            entranceFee: 0.01 ether, // 0.01 ETH
            interval: 30, // 30 seconds
            vrfCoordinatorV2_5: address(vrfCoordinatorV2_5Mock),
            gasLane: 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae, //随意 
            subscriptionId: subscriptionId, // update this with your subscriptionId
            callbackGasLimit: 500000,
            link: address(link),
            account: FOUNDRY_DEFAULT_SENDER
        });
        ///给账号充点钱
        vm.deal(localNetworkConfig.account, 100 ether);
        return localNetworkConfig;
                      
    }
} 