-include .env
RPC_URL ?= http://127.0.0.1:8545

.PHONY: all test clean deploy fund help install snapshot format anvil zktest deployMood

DEFAULT_ANVIL_KEY := 2a871d0798f97d79848a013d4936a73bf4cc922c825d33c1cf7073dff6d409c6
DEFAULT_ZKSYNC_LOCAL_KEY := 0x7726827caac94a7f9e1b160f7ea819f172f7b6f9d2a97f992c38edeab82d4110

all: clean remove install update build

# Clean the repo
clean  :; forge clean

# Remove modules
remove :; rm -rf .gitmodules && rm -rf .git/modules/* && rm -rf lib && touch .gitmodules && git add . && git commit -m "modules"

install :; forge install cyfrin/foundry-devops@0.2.2 --no-commit && forge install foundry-rs/forge-std@v1.8.2 --no-commit && forge install openzeppelin/openzeppelin-contracts@v5.0.2 --no-commit

# Update Dependencies
update:; forge update

build:; forge build

test :; forge test 

zktest :; foundryup-zksync && forge test --zksync && foundryup

snapshot :; forge snapshot

format :; forge fmt

anvil :; anvil -m 'test test test test test test test test test test test junk' --steps-tracing --block-time 1

NETWORK_ARGS := --rpc-url $(RPC_URL) --private-key $(PRIVATE_KEY) --broadcast

ifeq ($(findstring --network sepolia,$(ARGS)),--network sepolia)
	NETWORK_ARGS := --rpc-url $(SEPOLIA_RPC_URL) --private-key $(SEPOLIA_PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv
endif

check-anvil:
	@nc -z 127.0.0.1 8545 || (echo "Starting Anvil..." && anvil & sleep 2)
	@echo "Anvil is running on port 8545."

deploy-giftcard:
	@echo "Deploying GiftCard..."
	forge script script/DeployGiftCard.s.sol:DeployGiftCard  \
	--rpc-url $(SEPOLIA_RPC_URL) \
	--private-key $(SEPOLIA_PRIVATE_KEY) \
	--etherscan-api-key $(ETHERSCAN_API_KEY) \
	--verify \
	--broadcast -vvvv
	@echo "GiftCard deployed."

lisk-usdvalue:
	@echo "Calling usdValue..."
	cast call 0xae09ebCC43210d0cf8fF6a7495251FEACff86245 "usdValue(uint256)" 1000000000000000 --rpc-url $(SEPOLIA_RPC_URL) --private-key $(SEPOLIA_PRIVATE_KEY) -vvvv
	@echo "usdValue called."

lisk-ethvalue:
	@echo "Calling ethValue..."
	cast call 0xae09ebCC43210d0cf8fF6a7495251FEACff86245 "ethValue(uint256)" 2000000 --rpc-url $(SEPOLIA_RPC_URL) --private-key $(SEPOLIA_PRIVATE_KEY) -vvvv
	@echo "ethValue called."