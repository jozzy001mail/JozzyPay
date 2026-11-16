#!/usr/bin/env bash
# JozzyPay fork demo — full end-to-end run against a local fork of QDay Aevum.
# Uses the REAL tUSD8 contract (0x4565...3483) via the fork, and funds the
# demo payer by impersonating the tUSD8 faucet wallet (fork-only trick).
# No real assets move: everything happens on a local Anvil fork.
# Usage: bash demo/fork-demo.sh   (requires forge/cast + anvil)
set -euo pipefail

export PATH="$PATH:/home/hatch/.foundry/bin"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

TUSD8=0x456569838f1d43009A91ebA4263147Afd7233483
FAUCET_WALLET=0x4551B2a3dE4F43e6613E23edf798Ab4FB0211564
RPC=http://127.0.0.1:8545
# Anvil default accounts (well-known public test keys, fork-only — never mainnet)
MERCHANT_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
MERCHANT=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
PAYER_KEY=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
PAYER=0x70997970C51812dc3A010C7d01b50e0d17dc79C8

echo "== Starting Anvil fork of Aevum (chain 44005) =="
anvil --fork-url https://rpc-test.qday.info --chain-id 44005 --port 8545 > /tmp/anvil-fork.log 2>&1 &
ANVIL_PID=$!
trap 'kill $ANVIL_PID 2>/dev/null || true' EXIT
for i in $(seq 1 30); do
  if cast block-number --rpc-url $RPC >/dev/null 2>&1; then break; fi
  sleep 1
done
echo "fork block: $(cast block-number --rpc-url $RPC)"

echo "== Deploying JozzyPay =="
DEPLOY_OUT=$(forge script script/Deploy.s.sol --rpc-url $RPC --private-key $MERCHANT_KEY --broadcast --start-fresh 2>&1)
echo "$DEPLOY_OUT" | grep -E "JozzyPay deployed at|token:|owner:|maxInvoiceAmount"
JOZZYPAY=$(echo "$DEPLOY_OUT" | grep "JozzyPay deployed at:" | awk '{print $NF}')
echo "JozzyPay: $JOZZYPAY"

echo "== Funding demo payer with 100 tUSD8 (impersonating the faucet wallet, fork-only) =="
cast rpc anvil_impersonateAccount $FAUCET_WALLET --rpc-url $RPC >/dev/null
# Impersonated accounts still need gas on the fork: fund this one with 1 ETH.
cast rpc anvil_setBalance $FAUCET_WALLET 0xDE0B6B3A7640000 --rpc-url $RPC >/dev/null
cast send $TUSD8 "transfer(address,uint256)" $PAYER 100000000 --from $FAUCET_WALLET --unlocked --rpc-url $RPC >/dev/null
echo "payer tUSD8: $(cast call $TUSD8 "balanceOf(address)(uint256)" $PAYER --rpc-url $RPC) base units (100 tUSD8)"

echo "== Merchant creates invoice #0: 20 tUSD8, 'Business plan - Jozzyhub', 1 day expiry =="
EXPIRY=$(( $(date +%s) + 86400 ))
TX_CREATE=$(cast send $JOZZYPAY "createInvoice(uint256,uint256,string)" 20000000 $EXPIRY "Business plan - Jozzyhub" --private-key $MERCHANT_KEY --rpc-url $RPC --json 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin)['transactionHash'])" 2>/dev/null || echo "")
echo "create tx: ${TX_CREATE:-see broadcast log}"

echo "== Payer approves + pays invoice #0 =="
cast send $TUSD8 "approve(address,uint256)" $JOZZYPAY 20000000 --private-key $PAYER_KEY --rpc-url $RPC >/dev/null
TX_PAY=$(cast send $JOZZYPAY "payInvoice(uint256)" 0 --private-key $PAYER_KEY --rpc-url $RPC --json 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin)['transactionHash'])" 2>/dev/null || echo "")
echo "pay tx: ${TX_PAY:-see broadcast log}"
echo "escrow balance: $(cast call $TUSD8 "balanceOf(address)(uint256)" $JOZZYPAY --rpc-url $RPC) base units (expect 20000000)"

echo "== Merchant withdraws =="
TX_WD=$(cast send $JOZZYPAY "withdraw(uint256)" 0 --private-key $MERCHANT_KEY --rpc-url $RPC --json 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin)['transactionHash'])" 2>/dev/null || echo "")
echo "withdraw tx: ${TX_WD:-see broadcast log}"
echo "merchant tUSD8: $(cast call $TUSD8 "balanceOf(address)(uint256)" $MERCHANT --rpc-url $RPC) base units (expect 20000000)"
echo "escrow balance: $(cast call $TUSD8 "balanceOf(address)(uint256)" $JOZZYPAY --rpc-url $RPC) base units (expect 0)"

echo "== Invoice #0 final state =="
cast call $JOZZYPAY "getInvoice(uint256)((address,address,uint256,uint256,uint256,uint8,string))" 0 --rpc-url $RPC

echo "== Demo complete. JozzyPay: $JOZZYPAY =="
