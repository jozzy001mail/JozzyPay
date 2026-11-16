// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {JozzyPay} from "../src/JozzyPay.sol";

/// @notice Deploy JozzyPay to QDay Aevum testnet (chain ID 44005).
/// @dev Usage (deployer key must hold tQDAY for gas — see README.md):
///      forge script script/Deploy.s.sol \
///        --rpc-url https://rpc-test.qday.info \
///        --private-key $PRIVATE_KEY --broadcast
///      The token defaults to the official tUSD8 on Aevum; override with
///      TUSD8=<address>. The cap defaults to 10,000 tUSD8 (base units);
///      override with MAX_INVOICE=<base units>.
contract Deploy is Script {
    /// @notice Official tUSD8 on QDay Aevum testnet (6 decimals).
    address public constant TUSD8_AEVUM = 0x456569838f1d43009A91ebA4263147Afd7233483;

    /// @notice Default per-invoice cap: 10,000 tUSD8 in base units.
    uint256 public constant DEFAULT_CAP = 10_000 * 1e6;

    function run() external {
        address token = vm.envOr("TUSD8", TUSD8_AEVUM);
        uint256 cap = vm.envOr("MAX_INVOICE", DEFAULT_CAP);
        vm.startBroadcast();
        JozzyPay pay = new JozzyPay(IERC20(token), cap);
        vm.stopBroadcast();
        console.log("JozzyPay deployed at:", address(pay));
        console.log("token:", token);
        console.log("owner:", pay.owner());
        console.log("maxInvoiceAmount:", pay.maxInvoiceAmount());
        console.log("explorer:", string.concat("https://explorer-test.qday.info/address/", vm.toString(address(pay))));
    }
}
