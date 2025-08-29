// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.20;
import {Test,console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Raffle} from "../../src/Raffle.sol";
import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";

contract RaffleTest is Test {
    HelperConfig public helperConfig;
    Raffle public raffle;
    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_PLAYER_BLANCE = 10 ether;

    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint256 subscriptionId;
    uint32 callbackGasLimit;

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.deployContract();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        entranceFee = config.entranceFee;
        interval = config.interval;
        vrfCoordinator = config.vrfCoordinatorV2_5;
        gasLane = config.gasLane;
        subscriptionId = config.subscriptionId;
        callbackGasLimit = config.callbackGasLimit;

        ///给玩家充钱
        vm.deal(PLAYER,STARTING_PLAYER_BLANCE);
    }
    /*//////////////////////////////////////////////////////////////
                              抽奖
    //////////////////////////////////////////////////////////////*/
    //抽奖默认状态
    function testRaffleInitializesInOpenState() public view{
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }
     //支付不足回退
    function testRaffleRevertWhenYouDontPayEnough() public{
        //arrange 
        vm.prank(PLAYER);
        //act /asset
        vm.expectRevert(Raffle.Raffle__NotEnoughETHEntered.selector);
        raffle.enterRaffle();
        // 接下来的交易调用要模拟成 PLAYER 这个地址 发起的。
        // 预期会回退
        // 如果 raffle.enterRaffle() 里面有 msg.sender，它现在会被当作 PLAYER 而不是测试合约地址。
    }

     //测试玩家记录是否正确
    function testRaffleRecordsPlayersWhenTheyEnter() public{
        //arrange 
        vm.prank(PLAYER);
        //act /asset 
        raffle.enterRaffle{value:entranceFee}(); //抽奖
        address playerRecord = raffle.getPlayer(0);
        assert(playerRecord ==PLAYER);
    }

     //验证玩家进入抽奖时是否触发了 RaffleEntered 事件。
    function testEmitsEventOnEntrance() public {
        // Arrange
        vm.prank(PLAYER);
        // Act / Assert
        vm.expectEmit(true, false, false, false, address(raffle));
        emit Raffle.RaffleEntered(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        /**
         * 准备阶段（第一步）：调用 vm.expectEmit(...)，告诉 Foundry 接下来我们期待看到一个事件。
           模拟阶段（第二步）：手动 emit 一个事件，看上去“就像是”预期的那个。
           验证阶段（第三步）：执行你真正要测试的函数，Foundry 会把它发出的事件和你模拟的那个进行比对，看是否命中。
           这三个步骤缺一不可。如果比对成功了，测试就继续；如果没有，测试会失败，告诉你哪里不对。
         */
        /**
         vm.expectEmit(true, false, false, false, address(raffle));
        这行代码里有 5 个参数，我们逐个通俗解释一下：
        true —— “检查第一个主题（topic1）”。
        对应事件的第一个 indexed 参数，比如你这个 RaffleEntered(address indexed player)，就是检查它是哪个地址。

        false —— “不检查第二个主题（topic2）”。
        你这里的事件只有一个参数（player），也就是说只有 topic1，没有 topic2。所以不用检查这一项。

        false —— “不检查第三个主题（topic3）”。
        同理，因为你的事件本身只有一个 indexed 参数，所以第三个主题也不存在。

        false —— “不检查事件的非索引数据（data 部分）”。
        如果事件里还有非 indexed 的内容（比如 uint amount），这就是 data 部分。你的事件只是一个地址，没有额外数据，所以这里可以不用检查。

        address(raffle) —— “检查发出者是不是 raffle 这个合约”。
        Foundry 不仅会比对事件里的内容，还会确认事件是不是由你指定的那个合约（raffle）发出的。
         * 
        */
    }


    /**
     * 这个测试的逻辑就是：
     * 玩家先正常进入抽奖。
     * 快进时间，让抽奖周期结束。
     * 调用 performUpkeep，让状态进入「计算中」。
     * 预期：在「计算中」状态下，如果再有玩家想进入抽奖，交易应该 失败并回退。
    */

    function testDontAllowPlayersToEnterWhileRaffleIsCalculating() public {
         // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value:entranceFee}(); //抽奖
        ///修改时间
        vm.warp(block.timestamp + interval + 1); 
        vm.roll(block.number + 1);
        /**
         * warp：把区块的时间强制修改为当前时间 + interval + 1，相当于让时间往后快进一个抽奖周期。
         * roll：把区块号往后推进 1。
         * 这样就模拟了「抽奖周期到了，可以执行维护操作」。
         * */ 
        raffle.performUpkeep(bytes(""));
        /**
         * 调用 performUpkeep，即 Chainlink Keeper 触发的「维护操作」，进入 计算获胜者 的状态。
         * 此时，Raffle 的状态从 OPEN → CALCULATING。
         */
        // Act 告诉 Foundry：我预期接下来的操作会失败并 revert。
        vm.expectRevert(Raffle.Raffle__NotOpen.selector);
        // Arrange
        /**
          * 再次模拟 PLAYER 想进入抽奖。
          * 因为此时 Raffle 已经处于 CALCULATING 状态（正在开奖），不应该允许新玩家进入。
          * 于是，这里会触发 revert。
        * */ 
        vm.prank(PLAYER);
        raffle.enterRaffle{value:entranceFee}(); //抽奖
    }


    /*//////////////////////////////////////////////////////////////
                              CHECKUPKEEP
    //////////////////////////////////////////////////////////////*/
    function testCheckUpkeepReturnsFalseIfItHasNoBalance() public {
         /// 没有玩家就没有钱 
         //时间合法  
         vm.warp(block.timestamp + interval + 1); 
         vm.roll(block.number + 1); 

         //Act
        (bool upkeepNeeded,) = raffle.checkUpkeep("");
        //assert
        assert(!upkeepNeeded);
    }



    function testCheckUpkeepReturnsFalseIfRaffleIsntOpen() public {
         //arrage
         //进入抽奖 
         vm.prank(PLAYER);
         raffle.enterRaffle{value: entranceFee}();

         //时间合法  
         vm.warp(block.timestamp + interval + 1); 
         vm.roll(block.number + 1); 

        //请求抽奖状态更改为CALCULATING
        raffle.performUpkeep("");
        Raffle.RaffleState raffleState = raffle.getRaffleState();

         //Act
        (bool upkeepNeeded,) = raffle.checkUpkeep("");
        // Assert
        assert(raffleState == Raffle.RaffleState.CALCULATING);
        assert(upkeepNeeded == false);
    }

    function testCheckUpkeepReturnsFalseIfEnoughTimeHasntPassed() public {
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        // Act
        (bool upkeepNeeded,) = raffle.checkUpkeep("");
        // Assert
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsTrueWhenParametersGood() public {
         //arrage
         //进入抽奖 
         vm.prank(PLAYER);
         raffle.enterRaffle{value: entranceFee}();
         //时间合法  
         vm.warp(block.timestamp + interval + 1); 
         vm.roll(block.number + 1); 
         //act 
         (bool upkeepNeeded,) = raffle.checkUpkeep("");
         //assert
         assert(upkeepNeeded);
         
    }
     /*//////////////////////////////////////////////////////////////
                            PERFORM  UPKEEP
    //////////////////////////////////////////////////////////////*/
    function testPerformUpkeepCanOnlyRunIfCheckUpkeepIsTrue() public {
          // Arrange

        //玩家抽奖 - 更新时间戳  
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        // Act / Assert
        // It doesnt revert
        raffle.performUpkeep("");


    }
    function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public {
         // Arrange
        uint256 currentBalance = address(raffle).balance;
        uint256 numPlayers = 0;
        Raffle.RaffleState rState = raffle.getRaffleState();
        // Act / Assert
        vm.expectRevert(
            abi.encodeWithSelector(Raffle.Raffle__UpkeepNotNeeded.selector, currentBalance, numPlayers, rState)
        );
        raffle.performUpkeep("");
    }


    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId() public {
         // Arrange
        vm.prank(PLAYER); // 将下一次外部调用的 msg.sender 伪装成 PLAYER
        // 以 PLAYER 身份支付报名费进入抽奖。// 作用：合约里有玩家、有余额（满足 checkUpkeep 的玩家/余额条件）
        raffle.enterRaffle{value: entranceFee}(); 
        //// 把当前区块时间快进到 “当前时间 + interval + 1”
       // 注意你的合约用的是 “> i_interval” 的严格大于判断，所以这里 +1 保证时间条件成立
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        // Act
        vm.recordLogs(); // 开始录制从这一刻起产生的所有日志（包括本函数内以及子调用产生的事件logs）
        raffle.performUpkeep(""); // emits requestId

        // 取回刚才录制到的所有日志（事件）。每一条包含 emitter（发出日志的合约地址）、topics、data 等
        Vm.Log[] memory entries = vm.getRecordedLogs();
        // 从第二条日志（entries[1]）里取第一个 indexed 参数（topics[1]），作为 requestId。
        // 约定俗成：
        // - topics[0] 是事件签名（keccak hash）
        // - topics[1] 是该事件的第一个 indexed 参数
        // 这里假设第2条日志正好是 VRF Coordinator 的 “RandomWordsRequested” 事件，
        // 且其第一个 indexed 参数就是 requestId。
       // 注意：这对日志顺序和事件签名有假设，实际项目可能需要更稳妥的筛选（见下方“小提示”）
        bytes32 requestId = entries[1].topics[1];

        // Assert
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        // requestId = raffle.getLastRequestId();
        // 验证从日志里拿到的 requestId 非零，说明确实发起了 VRF 请求
        assert(uint256(requestId) > 0);
        assert(uint256(raffleState) == 1); // 0 = open, 1 = calculating
    }
     /*//////////////////////////////////////////////////////////////
                           FULFILLRANDOMWORDS
    //////////////////////////////////////////////////////////////*/
     modifier raffleEntered() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    modifier skipFork() {
        if (block.chainid != 31337) {
            return;
        }
        _;
    }

    function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep() public raffleEntered skipFork {
        // Arrange
        // Act / Assert
        vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
        // vm.mockCall could be used here...
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(0, address(raffle));

        vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(1, address(raffle));
    }

    // function testFulfillRandomWordsPicksAWinnerResetsAndSendsMoney() public raffleEntered skipFork {

    //     // Arrange
    //     //预期的赢家的，模拟返回的随机数总是为1，% 4（4个玩家） = 1
    //     address expectedWinner = address(1);
    //     //4 个玩家抽奖
    //     uint256 additionalEntrances = 3;
    //     uint256 startingIndex = 1; // 从 1 开始循环，这样生成的玩家地址从 address(1) 起（避免 address(0)）。

    //     for (uint256 i = startingIndex; i < startingIndex + additionalEntrances; i++) {
    //         address player = address(uint160(i));
    //         hoax(player, 1 ether); // deal 1 eth to the player。每个玩家充值1ether
    //         raffle.enterRaffle{value: entranceFee}();
    //     }
    //     //获取时间
    //     uint256 startingTimeStamp = raffle.getLastTimeStamp();

    //     //记录期望中奖者 address(1) 在触发 VRF 之前的余额（此时他已经作为玩家之一并且付过 entranceFee，所以余额是付费后的余额），
    //     //后续会用来断言中奖后余额增加量是否正确。
    //     uint256 startingBalance = expectedWinner.balance; 

    //     // Act
    //     vm.recordLogs();
    //     raffle.performUpkeep(""); // emits requestId
    //     Vm.Log[] memory entries = vm.getRecordedLogs();
    //     /**
    //      * 打印调试用：把第二个 log 的第二个 topic（topics[1]，topic 索引从 0 开始）以 bytes32 打印出来，
    //      * 方便在控制台查看（用于调试和确认请求 ID 的位置）。
    //     注意：为什么 entries[1]？通常第 0 条 log 可能是其他事件（或索引不同），
    //     开发者事先知道 requestId 在 entries[1].topics[1]，所以直接取第二条 log。
    //      * 
    //     */
    //     console.logBytes32(entries[1].topics[1]);
    //     bytes32 requestId = entries[1].topics[1]; // get the requestId from the logs
    //     /**
    //      * 用已部署的 VRF mock 模拟器（VRFCoordinatorV2_5Mock）去“完成（fulfill）”随机词（random words）的回调：
    //         将 bytes32 requestId 强转为 uint256，并把请求回调目标设为抽奖合约 address(raffle)。
    //         这一步等价于模拟 Chainlink 节点返回随机数，mock 会调用 raffle.rawFulfillRandomWords 或合约中对应的回调函数，
    //         从而触发抽奖合约根据随机数选出中奖者并转账奖金、更新状态等。


    //         测试环境下的随机数不是“真随机”
    //         你用的是 VRFCoordinatorV2_5Mock。
    //         这个 Mock 是 Chainlink 提供的，它不会调用真实的预言机，而是：
    //         在你调用
    //         fulfillRandomWords(requestId, raffleAddress)
    //         的时候，Mock 就直接调用 raffle.rawFulfillRandomWords(requestId, fixedRandomWords)。
    //         这里的 fixedRandomWords 是固定的数组（通常就是 [uint256(1)]，有的版本是递增数字）。
    //         👉 也就是说，每次测试里 VRF mock 返回的随机数都是“1”。
    //         winnerIndex = 1 % 4 = 1
    //         winner = players[1] = address(1)
    //         就和 expectedWinner = address(1) 完全对上了 ✅。
    //     */
    //     VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(raffle));

    //     // Assert
    //     address recentWinner = raffle.getRecentWinner();
    //     Raffle.RaffleState raffleState = raffle.getRaffleState();
    //     uint256 winnerBalance = recentWinner.balance;
    //     uint256 endingTimeStamp = raffle.getLastTimeStamp();
    //     uint256 prize = entranceFee * (additionalEntrances + 1);//奖金

    //     console.log("entranceFee:", entranceFee);
    //     console.log("players:", raffle.getPlayerNumbers());
    //     console.log("contract balance:", address(raffle).balance);
    //     console.log("prize:", prize);

    //     assert(recentWinner == expectedWinner);
    //     assert(uint256(raffleState) == 0);

    //     assert(winnerBalance == startingBalance + prize);
    //     assert(endingTimeStamp > startingTimeStamp);
    // }
}
