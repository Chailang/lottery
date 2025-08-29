// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.20; 
import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";

contract Raffle is VRFConsumerBaseV2Plus,AutomationCompatibleInterface{ //抽奖
    /**errors */
    error Raffle__NotEnoughETHEntered(); //自定义错误，表示支付的ETH不足
    error Raffle__TransferFailed(); //中奖者发送失败
    error Raffle__NotOpen(); //中奖者发送失败
    error Raffle_TimerIntervalNotNnough();
    error Raffle__UpkeepNotNeeded(uint256 currentBalance, uint256 numPlayers, uint256 raffleState);


    /**Type declarations*/
    enum RaffleState {
        OPEN,
        CALCULATING
    } //彩票状态枚举
  
    /**TState variables*/
    uint256 public immutable i_entranceFee; //入场费
    //@dev 彩票运行的间隔周期
    uint256 public immutable i_interval; //间隔周期
    uint256 public s_lastTimeStamp;     //上一次开奖时间
    address payable[] public s_players; //玩家地址数组
    address public s_recentWinner; //最近的赢家地址
    RaffleState private s_raffleState; //彩票状态变量


     // Chainlink VRF Variables
    bytes32 private immutable i_keyHash;
    uint256 private immutable i_subscriptionId;
    bytes32 private immutable i_gasLane;
    uint32 private immutable i_callbackGasLimit;
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;
    

    /**Events */
    event RaffleEntered(address indexed player); //玩家进入抽奖事件
    event RaffleWinnerPicked(address indexed winner); //玩家中奖事件
    event RequestedRaffleWinner(uint256 indexed requestId); //请求 id

    
    /**function */
    constructor(uint256 entranceFee,
                uint256 interval, 
                address vrfCoordinator,
                bytes32 gasLane,
                uint256 subscriptionId,
                uint32 callbackGasLimit
     ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        s_lastTimeStamp = block.timestamp; //初始化上一次开奖时间为当前时间
        s_raffleState = RaffleState.OPEN; //初始化彩票状态为OPEN
        // Chainlink VRF Initialization
        i_keyHash = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit; 
    }

 
    function enterRaffle() external payable { //进入抽奖
        //require(msg.value >= i_entranceFee, "Not enough ETH!"); //确保支付的ETH不少于入场费
        if (msg.value < i_entranceFee) { 
            revert Raffle__NotEnoughETHEntered(); //使用自定义错误 更节省gas
        }
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__NotOpen();//彩票状态不是OPEN，不能进入
        }
        s_players.push(payable(msg.sender)); //将玩家地址添加到数组中
        emit RaffleEntered(msg.sender); //触发玩家进入抽奖事件
    }
    
   
    ///CEI pattern check, effects, interactions // 模式 检查，影响，交互
    ///获取到随机数后的处理
    function fulfillRandomWords(uint256, uint256[] calldata randomWords) internal override {
        uint256 indexOfWinner = randomWords[0] % s_players.length; //通过随机数选择赢家
        address payable recentWinner = s_players[indexOfWinner]; //获取赢家地址
        s_recentWinner = recentWinner; //更新最近的赢家地址
        s_raffleState = RaffleState.OPEN; //将彩票状态设置为OPEN
         //重置彩票
        s_players = new address payable[](0);
        s_lastTimeStamp = block.timestamp; //更新上一次开奖时间为当前时间


        //将合约中的余额发送给赢家
        (bool success, ) = recentWinner.call{value: address(this).balance}("");
        if (success == false) {
            revert Raffle__TransferFailed();
        }
        emit RaffleWinnerPicked(recentWinner); //触发玩家中奖事件
       
    }

    /**
     * @dev This is the function that the Chainlink Keeper nodes call
     * they look for `upkeepNeeded` to return True.
     * the following should be true for this to return true:
     * 1. The time interval has passed between raffle runs.
     * 2. The lottery is open.
     * 3. The contract has ETH.
     * 4. Implicity, your subscription is funded with LINK.
     */
   function checkUpkeep(
        bytes calldata /* checkData */
    )
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        bool isOpen = (s_raffleState == RaffleState.OPEN); //彩票状态是否为OPEN
        bool timePassed = ((block.timestamp - s_lastTimeStamp) > i_interval); //是否达到间隔周期
        bool hasPlayers = (s_players.length > 0); //是否有玩家
        bool hasBalance = address(this).balance > 0; //合约中是否有余额
        upkeepNeeded = (isOpen && timePassed && hasPlayers && hasBalance); //只有满足以上条件，才需要执行维护
        performData = bytes(""); //这里不需要传递任何数据
       
    }

    /**
     * @dev Once `checkUpkeep` is returning `true`, this function is called
     * and it kicks off a Chainlink VRF call to get a random winner.
     * 
     * // 1. 选择随机数
        // 2. 选择赢家
        // 3. 发放奖金
        // 4. 重置彩票
        // 5. 记录时间戳
     */
     function performUpkeep(bytes calldata /* performData */) external override {
       (bool upkeepNeeded,) = this.checkUpkeep(bytes(""));
       if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(address(this).balance, s_players.length, uint256(s_raffleState));
       }
         s_raffleState = RaffleState.CALCULATING; //将彩票状态设置为CALCULATING，表示正在计算赢家
        //请求随机数
        VRFV2PlusClient.RandomWordsRequest memory request = VRFV2PlusClient.RandomWordsRequest({
                keyHash: i_keyHash,
                subId: i_subscriptionId,
                requestConfirmations: REQUEST_CONFIRMATIONS,
                callbackGasLimit: i_callbackGasLimit,
                numWords: NUM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({
                        nativePayment: false
                    })
                )
        });
        uint256 requestId = s_vrfCoordinator.requestRandomWords(request); 
        emit RequestedRaffleWinner(requestId);
    }

    function getEntranceFee() public view returns (uint256) { //获取入场费
        return i_entranceFee;
    }
    function getRaffleState() public view returns (RaffleState){
        return s_raffleState;
    }
    function getPlayer(uint256 indexOfPlayer) public view returns (address){
        return s_players[indexOfPlayer];
    }
}
//整体流程循环：部署 → 多用户enterRaffle（累积玩家/资金） → Keeper checkUpkeep（定期） → performUpkeep → pickWinner（VRF请求） → fulfillRandomWords（回调） → 重置 → 循环。

