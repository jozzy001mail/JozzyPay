# JozzyPay — 3-minute demo script

## What to show (live, on the Aevum testnet UI)

1. **(0:00–0:20) The problem.** "A small business in Nigeria wants to take
   stablecoin payments. Today that's a wallet address pasted into WhatsApp —
   wrong amounts, no receipt, no way back. JozzyPay is a payment link."
2. **(0:20–0:50) Create.** Connect MetaMask to QDay Aevum (chain 44005).
   Create an invoice: **20 tUSD8**, memo **"Business plan — Jozzyhub"**,
   expiry 24 hours. Point at the new invoice #N, status OPEN, on screen.
3. **(0:50–1:30) Pay.** Switch to the customer account (it holds tUSD8).
   Click Pay — the UI approves tUSD8 once, then pays. Show the transaction
   on the Aevum explorer and the invoice flipping to PAID, funds in escrow.
4. **(1:30–2:10) Withdraw.** Switch back to the merchant account. Click
   Withdraw. Show the merchant's tUSD8 balance rising by 20 and the invoice
   flipping to SETTLED. Point at the explorer link.
5. **(2:10–2:45) The safety net.** Create a second invoice, pay it, let it
   expire (or show an already-expired one) and click Refund as the payer —
   the money comes back. Mention the per-invoice spend cap (10,000 tUSD8):
   "an agent paying for you can never move more than one invoice's cap."
6. **(2:45–3:00) Close.** "JozzyPay: payment links for small businesses,
   on QDay Aevum, in tUSD8. Code is open source, the contract is verified on
   the explorer."

## Recorded evidence — local fork run (real tUSD8 contract code)

The full flow was already executed end-to-end against a local fork of Aevum
(`bash demo/fork-demo.sh`), using the real tUSD8 contract at
`0x456569838f1d43009A91ebA4263147Afd7233483`. Fork transaction hashes:

| Step | Transaction (fork) |
| --- | --- |
| Deploy JozzyPay | contract `0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9` (fork) |
| Create invoice #0 (20 tUSD8, "Business plan — Jozzyhub") | `0x8e83d526eabf001da95e22f9b9f205659d87ec11cb2cf5bc05c62104009d23e5` |
| Pay invoice #0 | `0xf6584d2f093cfd94d31a3d5549f35457ee871ce0618698bbdd2f67d783dd3077` |
| Withdraw invoice #0 | `0x77e611218f31831a2aed5b318d73e8ad185f0479c988fdcd993ef71a1d8c7798` |

Final state check (fork): invoice #0 = merchant `0xf39F…2266`, payer
`0x7099…79C8`, amount 20,000,000 base units (20 tUSD8), status `2`
(SETTLED), escrow balance 0. **Note:** these are fork hashes, not live
Aevum transactions — the live run will produce new hashes on the explorer
once the contract is deployed with funded test tokens.

## Still to capture

- A screen recording of the live UI walkthrough above (once deployed).
- Only the Top 5 finalists do the live 3–5 minute Demo Day video call on
  15 Dec — a recorded demo strengthens the entry but is not a formal
  submission requirement for all entrants.
