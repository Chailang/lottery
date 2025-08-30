-include .env

DEFAULT_ANVIL_KEY := 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

.PHONY: all test deploy

all: clean remove install update build

# 默认目标，执行一系列操作：
# clean → 清理项目
# remove → 删除模块
# install → 安装依赖
# update → 更新依赖
# build → 编译合约

build:
	forge build
test:
	forge test
snapshot:
	 forge snapshot

# Clean the repo
clean:
	forge clean
# Remove modules
remove: 
	rm -rf .gitmodules && rm -rf .git/modules/* && rm -rf lib && touch .gitmodules && git add . && git commit -m "modules"

install:
	forge install cyfrin/foundry-devops@0.2.2 && forge install smartcontractkit/chainlink-brownie-contracts@1.1.1 && forge install foundry-rs/forge-std@v1.8.2 && forge install transmissions11/solmate@v6

# Update Dependencies
update:
	forge update	

#启动本地 Anvil 节点
# 使用固定助记词生成账户
# --steps-tracing → 启用交易执行步骤追踪
# --block-time 1 → 区块时间为 1 秒	 
anvil: 
	anvil -m 'test test test test test test test test test test test junk' --steps-tracing --block-time 1


# 默认网络参数（本地 Anvil）：
# RPC 地址
# 私钥
# --broadcast → 执行真实交易
NETWORK_ARGS := --rpc-url http://localhost:8545 --private-key $(DEFAULT_ANVIL_KEY) --broadcast

# 如果 ARGS 包含 --network sepolia：
# 使用 Sepolia 测试网 RPC
# 用 .env 中的私钥和 Etherscan API
# --verify → 部署后自动验证合约
# -vvvv → 打印详细日志
ifeq ($(findstring --network sepolia,$(ARGS)),--network sepolia)
	NETWORK_ARGS := --rpc-url $(SEPOLIA_RPC_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv
endif


deploy:
	@forge script script/DeployRaffle.s.sol:DeployRaffle $(NETWORK_ARGS)

createSubscription:
	@forge script script/Interactions.s.sol:CreateSubscription $(NETWORK_ARGS)

addConsumer:
	@forge script script/Interactions.s.sol:AddConsumer $(NETWORK_ARGS)

fundSubscription:
	@forge script script/Interactions.s.sol:FundSubscription $(NETWORK_ARGS)

# 这个 Makefile 是一个 Foundry 项目自动化工具：
# 管理依赖（install/update/remove）
# 编译与格式化合约（build/format）
# 本地测试与快照（test/snapshot/anvil）
# 自动化部署和交互脚本（deploy/createSubscription/...）
# 支持本地 Anvil 和远程测试网（Sepolia）