# JozzyPay — stablecoin payment links for small businesses

**Aevum Builder Challenge #1 — DoraHacks** · Solo entry by Owoade (builder
[@owoade](https://dorahacks.io/builder/owoade)) · Chain: QDay Aevum testnet
(44005) · Token: tUSD8

## The problem

A small business in Nigeria — a shop, a CV writer, a food vendor — wants to
take payments in stablecoin. Today that means pasting a wallet address into
WhatsApp and hoping the customer sends the right amount to the right place,
with no receipt, no expiry, and no way back if the seller disappears.
JozzyPay turns that into a **payment link**: the seller creates an invoice,
the buyer pays exactly that amount into escrow, and the seller withdraws it.
If the seller never withdraws and the invoice expires, the buyer gets a
refund. Every step is on-chain and checkable on the explorer.

## The flow

```
Merchant ── createInvoice(amount, expiresAt, memo) ──▶ JozzyPay (escrow)
Buyer    ── approve(tUSD8) ──▶ payInvoice(id) ──▶ funds locked in escrow
Merchant ── withdraw(id) ──▶ tUSD8 to merchant
   — or, if expired and never withdrawn —
Buyer    ── refund(id) ──▶ tUSD8 back to buyer
Merchant ── cancel(id) ──▶ only while OPEN (unpaid)
```

## Safety properties

- **Pull payments only.** The contract never pushes funds except on an
  explicit `withdraw` / `refund` by the entitled party.
- **Per-invoice spend cap** (`maxInvoiceAmount`, default 10,000 tUSD8).
  This is the agent primitive: an AI agent paying on a user's behalf through
  an ERC20 allowance can never move more than one invoice's cap per payment,
  so a compromised agent key cannot drain a wallet. The owner can adjust the
  cap; that is the owner's *only* power — it never touches escrowed funds.
- **Expiry.** An open invoice cannot be paid after `expiresAt`; a paid
  invoice can only be refunded after `expiresAt`.
- **ReentrancyGuard** on `payInvoice`, `withdraw` and `refund`;
  **SafeERC20** for all token moves; custom errors throughout.
- No admin keys over user funds, no upgradeability, no hidden fees.

## Architecture

```
app/                  Static UI (no build step) — ethers v6, MetaMask
  index.html          Create / pay / withdraw / refund / cancel + invoice list
  config.js           Chain, token and deployed contract addresses
src/JozzyPay.sol      The escrow contract (Solidity 0.8.24, Foundry)
test/JozzyPay.t.sol   24 tests incl. a 256-run fuzz test (all passing)
script/Deploy.s.sol   Deployment script for Aevum testnet
demo/fork-demo.sh     End-to-end run on a local fork of Aevum (real tUSD8)
demo/DEMO.md          3-minute demo script + fork-run evidence
Dockerfile            nginx image serving the UI (alternative live deployment)
```

## Testnet addresses (QDay Aevum, chain ID 44005)

| What | Value |
| --- | --- |
| RPC | `https://rpc-test.qday.info` |
| Explorer | `https://explorer-test.qday.info` |
| tUSD8 (6 decimals) | `0x456569838f1d43009A91ebA4263147Afd7233483` |
| QDay faucet (tQDAY gas) | `0xE5074CBbd046AFb491EB8692abD6cF7ECCC6dEE5` |
| tUSD8 faucet wallet | `0x4551B2a3dE4F43e6613E23edf798Ab4FB0211564` |
| **JozzyPay (live)** | **TBD — deploy pending test-token funding (see below)** |
| JozzyPay (local fork demo) | `0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9` |

## Run the tests

```bash
forge test
```

24 tests, including a fuzz test over the full create → pay → withdraw flow.
`forge build` compiles clean with no warnings.

## Run the end-to-end demo on a fork (no test tokens needed)

```bash
bash demo/fork-demo.sh
```

Starts an Anvil fork of Aevum, deploys JozzyPay, funds a demo payer with
100 tUSD8 (by impersonating the tUSD8 faucet wallet — fork-only trick),
creates a 20 tUSD8 invoice, pays it, withdraws it, and prints every
transaction hash. See `demo/DEMO.md` for the recorded run.

## Deploy to live Aevum testnet

The deploy script is ready; what is missing is **test tokens in the deployer
wallet** (deployer `0x0170830e15Db23fe1816F06507a63F07cEC187a9`, key in
`.deployer.json` — testnet-only throwaway, never committed).

1. **tQDAY (gas)** — claim at <https://faucet.qday.info>. Two gates found by
   probing the faucet's own API:
   - a captcha must be solved in the browser, and
   - the address must hold **≥ 0.0001 ETH on Ethereum mainnet** (verified:
     an address holding mainnet ETH is `eligible: true`; a fresh wallet and
     Owoade's BSC wallet are `eligible: false`).
   If no controlled address passes, the intended path is the challenge
   **starter kit on Discord** (`discord.gg/bYPhjmrSfK`) — ask the QDay team
   there for builder test tokens.
2. **tUSD8 (payment token)** — claim at the same faucet site, **1 tUSD8 per
   24h**, via an **email code**: enter an email, paste the code from the
   inbox, then claim. (The `/api/tusd8` endpoint is email-gated, not
   captcha-gated.)
3. Deploy and verify:

```bash
export PRIVATE_KEY=<deployer key>   # testnet only, never mainnet
forge script script/Deploy.s.sol \
  --rpc-url https://rpc-test.qday.info \
  --private-key $PRIVATE_KEY --broadcast
# then verify the source on the Blockscout explorer:
forge verify-contract <DEPLOYED_ADDRESS> src/JozzyPay.sol:JozzyPay \
  --chain-id 44005 --rpc-url https://rpc-test.qday.info \
  --verifier blockscout --verifier-url https://explorer-test.qday.info/api \
  --constructor-args $(cast abi-encode "constructor(address,uint256)" \
    0x456569838f1d43009A91ebA4263147Afd7233483 10000000000)
```

4. Put the deployed address in `app/config.js` (`contractAddress`).

## Run the UI

```bash
# any static server, e.g.:
python3 -m http.server 8000 -d app
# open http://localhost:8000 — connect MetaMask, switch to QDay Aevum (44005)
```

Or with Docker (serves the UI on port 80):

```bash
docker build -t jozzypay .
docker run -p 8080:80 jozzypay
```

The UI works against any deployment: paste a contract address into the
address field and it reloads against that contract.

## Submission checklist (DoraHacks)

- [x] Public GitHub repository with clean, readable code — *repo to be
      published from this directory (see below)*
- [ ] Live deployment on Aevum testnet + verified source — *blocked only on
      test-token funding (see "Deploy" above)*
- [x] Working interface (`app/`) + Docker image (`Dockerfile`)
- [x] Documentation (this README + `demo/DEMO.md`)
- [ ] Demo video — script in `demo/DEMO.md`; a recorded walkthrough is
      still to be captured (only the Top 5 do the live 3–5 min Demo Day call
      on 15 Dec)
- [x] No malicious code; test tokens only

## Publishing the repo

This directory is a git repo with clean, reviewable commits. Push it to a
**public** GitHub repository (e.g. `jozzy001mail/JozzyPay`) and use that URL
in the DoraHacks submission form. The deployer key (`.deployer.json`) is
git-ignored and must never be committed.

## Challenge facts (verified live 16 Nov 2026)

- Event: Aevum Builder Challenge #1,
  <https://dorahacks.io/hackathon/qday/detail>
- Prizes: **$1,500 USDT** — 1st $800, 2nd $500, 3rd $200
- Build: 16 Nov – 11 Dec 2026 · **Submissions close 11 Dec 2026, 08:00 UTC**
- Judging: 12–14 Dec · Demo Day (Top 5, 3–5 min live call): 15 Dec 2026
- Solo developers allowed; all code built during the window; testnet only
- Fast track into the QDay mainnet builder program (mainnet Feb 2027)

## License

MIT
