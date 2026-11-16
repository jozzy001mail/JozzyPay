// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {JozzyPay} from "../src/JozzyPay.sol";

/// @notice Minimal 6-decimal mintable stablecoin stand-in for tUSD8.
contract MockUSD8 is ERC20 {
    constructor() ERC20("test USD8", "tUSD8") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract JozzyPayTest is Test {
    JozzyPay public pay;
    MockUSD8 public usd8;

    address public merchant = makeAddr("merchant");
    address public payer = makeAddr("payer");
    address public stranger = makeAddr("stranger");

    uint256 public constant CAP = 10_000 * 1e6; // 10,000 tUSD8
    uint256 public constant AMOUNT = 20 * 1e6; // 20 tUSD8

    function setUp() public {
        usd8 = new MockUSD8();
        pay = new JozzyPay(IERC20(address(usd8)), CAP);
        usd8.mint(payer, CAP);
        usd8.mint(merchant, 100 * 1e6);
        vm.prank(payer);
        usd8.approve(address(pay), type(uint256).max);
    }

    function _createInvoice() internal returns (uint256 id) {
        vm.prank(merchant);
        id = pay.createInvoice(AMOUNT, block.timestamp + 1 days, "CV writing - Jozzyhub");
    }

    function _createAndPay() internal returns (uint256 id) {
        id = _createInvoice();
        vm.prank(payer);
        pay.payInvoice(id);
    }

    // ---- create ----

    function testCreateInvoice() public {
        vm.prank(merchant);
        vm.expectEmit(true, true, false, true);
        emit JozzyPay.InvoiceCreated(0, merchant, AMOUNT, block.timestamp + 1 days, "CV writing - Jozzyhub");
        uint256 id = pay.createInvoice(AMOUNT, block.timestamp + 1 days, "CV writing - Jozzyhub");
        assertEq(id, 0);
        JozzyPay.Invoice memory inv = pay.getInvoice(0);
        assertEq(inv.merchant, merchant);
        assertEq(inv.payer, address(0));
        assertEq(inv.amount, AMOUNT);
        assertEq(uint256(inv.status), uint256(JozzyPay.Status.OPEN));
        assertEq(pay.nextInvoiceId(), 1);
    }

    function testCreateZeroAmountReverts() public {
        vm.prank(merchant);
        vm.expectRevert(JozzyPay.AmountZero.selector);
        pay.createInvoice(0, block.timestamp + 1 days, "x");
    }

    function testCreateOverCapReverts() public {
        vm.prank(merchant);
        vm.expectRevert(abi.encodeWithSelector(JozzyPay.AmountExceedsCap.selector, CAP + 1, CAP));
        pay.createInvoice(CAP + 1, block.timestamp + 1 days, "x");
    }

    function testCreateAtCapSucceeds() public {
        vm.prank(merchant);
        uint256 id = pay.createInvoice(CAP, block.timestamp + 1 days, "max");
        assertEq(pay.getInvoice(id).amount, CAP);
    }

    function testCreatePastExpiryReverts() public {
        vm.prank(merchant);
        vm.expectRevert(abi.encodeWithSelector(JozzyPay.ExpiryInPast.selector, block.timestamp - 1, block.timestamp));
        pay.createInvoice(AMOUNT, block.timestamp - 1, "x");
    }

    // ---- pay ----

    function testPayInvoice() public {
        uint256 id = _createInvoice();
        uint256 payerBefore = usd8.balanceOf(payer);
        vm.prank(payer);
        vm.expectEmit(true, true, false, true);
        emit JozzyPay.InvoicePaid(id, payer, AMOUNT);
        pay.payInvoice(id);
        JozzyPay.Invoice memory inv = pay.getInvoice(id);
        assertEq(uint256(inv.status), uint256(JozzyPay.Status.PAID));
        assertEq(inv.payer, payer);
        assertEq(inv.paidAt, block.timestamp);
        assertEq(usd8.balanceOf(payer), payerBefore - AMOUNT);
        assertEq(usd8.balanceOf(address(pay)), AMOUNT);
    }

    function testPayTwiceReverts() public {
        uint256 id = _createAndPay();
        vm.prank(payer);
        vm.expectRevert(abi.encodeWithSelector(JozzyPay.WrongStatus.selector, id, JozzyPay.Status.PAID));
        pay.payInvoice(id);
    }

    function testPayExpiredReverts() public {
        uint256 start = vm.getBlockTimestamp();
        uint256 id = _createInvoice();
        vm.warp(start + 1 days + 1);
        vm.prank(payer);
        vm.expectRevert(
            abi.encodeWithSelector(JozzyPay.InvoiceExpired.selector, id, start + 1 days, start + 1 days + 1)
        );
        pay.payInvoice(id);
    }

    function testPayWithoutApprovalReverts() public {
        uint256 id = _createInvoice();
        address noApproval = makeAddr("noApproval");
        usd8.mint(noApproval, AMOUNT);
        vm.prank(noApproval);
        vm.expectRevert();
        pay.payInvoice(id);
    }

    // ---- withdraw ----

    function testWithdraw() public {
        uint256 id = _createAndPay();
        uint256 merchantBefore = usd8.balanceOf(merchant);
        vm.prank(merchant);
        vm.expectEmit(true, true, false, true);
        emit JozzyPay.InvoiceSettled(id, merchant, AMOUNT);
        pay.withdraw(id);
        assertEq(uint256(pay.getInvoice(id).status), uint256(JozzyPay.Status.SETTLED));
        assertEq(usd8.balanceOf(merchant), merchantBefore + AMOUNT);
        assertEq(usd8.balanceOf(address(pay)), 0);
    }

    function testWithdrawNotMerchantReverts() public {
        uint256 id = _createAndPay();
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(JozzyPay.NotMerchant.selector, stranger, merchant));
        pay.withdraw(id);
    }

    function testWithdrawUnpaidReverts() public {
        uint256 id = _createInvoice();
        vm.prank(merchant);
        vm.expectRevert(abi.encodeWithSelector(JozzyPay.WrongStatus.selector, id, JozzyPay.Status.OPEN));
        pay.withdraw(id);
    }

    function testWithdrawTwiceReverts() public {
        uint256 id = _createAndPay();
        vm.prank(merchant);
        pay.withdraw(id);
        vm.prank(merchant);
        vm.expectRevert(abi.encodeWithSelector(JozzyPay.WrongStatus.selector, id, JozzyPay.Status.SETTLED));
        pay.withdraw(id);
    }

    // ---- refund ----

    function testRefundAfterExpiry() public {
        uint256 start = vm.getBlockTimestamp();
        uint256 id = _createAndPay();
        vm.warp(start + 1 days + 1);
        uint256 payerBefore = usd8.balanceOf(payer);
        vm.prank(payer);
        vm.expectEmit(true, true, false, true);
        emit JozzyPay.InvoiceRefunded(id, payer, AMOUNT);
        pay.refund(id);
        assertEq(uint256(pay.getInvoice(id).status), uint256(JozzyPay.Status.REFUNDED));
        assertEq(usd8.balanceOf(payer), payerBefore + AMOUNT);
        assertEq(usd8.balanceOf(address(pay)), 0);
    }

    function testRefundBeforeExpiryReverts() public {
        uint256 start = vm.getBlockTimestamp();
        uint256 id = _createAndPay();
        vm.prank(payer);
        vm.expectRevert(abi.encodeWithSelector(JozzyPay.InvoiceNotExpired.selector, id, start + 1 days, start));
        pay.refund(id);
    }

    function testRefundNotPayerReverts() public {
        uint256 start = vm.getBlockTimestamp();
        uint256 id = _createAndPay();
        vm.warp(start + 1 days + 1);
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(JozzyPay.NotPayer.selector, stranger, payer));
        pay.refund(id);
    }

    function testRefundAfterWithdrawReverts() public {
        uint256 start = vm.getBlockTimestamp();
        uint256 id = _createAndPay();
        vm.prank(merchant);
        pay.withdraw(id);
        vm.warp(start + 1 days + 1);
        vm.prank(payer);
        vm.expectRevert(abi.encodeWithSelector(JozzyPay.WrongStatus.selector, id, JozzyPay.Status.SETTLED));
        pay.refund(id);
    }

    // ---- cancel ----

    function testCancelOpen() public {
        uint256 id = _createInvoice();
        vm.prank(merchant);
        vm.expectEmit(true, false, false, true);
        emit JozzyPay.InvoiceCancelled(id);
        pay.cancel(id);
        assertEq(uint256(pay.getInvoice(id).status), uint256(JozzyPay.Status.CANCELLED));
        vm.prank(payer);
        vm.expectRevert(abi.encodeWithSelector(JozzyPay.WrongStatus.selector, id, JozzyPay.Status.CANCELLED));
        pay.payInvoice(id);
    }

    function testCancelPaidReverts() public {
        uint256 id = _createAndPay();
        vm.prank(merchant);
        vm.expectRevert(abi.encodeWithSelector(JozzyPay.WrongStatus.selector, id, JozzyPay.Status.PAID));
        pay.cancel(id);
    }

    function testCancelNotMerchantReverts() public {
        uint256 id = _createInvoice();
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(JozzyPay.NotMerchant.selector, stranger, merchant));
        pay.cancel(id);
    }

    // ---- cap management ----

    function testSetCap() public {
        vm.expectEmit(false, false, false, true);
        emit JozzyPay.MaxInvoiceAmountUpdated(500 * 1e6);
        pay.setMaxInvoiceAmount(500 * 1e6);
        assertEq(pay.maxInvoiceAmount(), 500 * 1e6);
    }

    function testSetCapNotOwnerReverts() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(JozzyPay.NotOwner.selector, stranger, address(this)));
        pay.setMaxInvoiceAmount(500 * 1e6);
    }

    function testSetCapZeroReverts() public {
        vm.expectRevert(JozzyPay.AmountZero.selector);
        pay.setMaxInvoiceAmount(0);
    }

    // ---- fuzz ----

    function testFuzzCreatePayWithdraw(uint256 amount) public {
        amount = bound(amount, 1, CAP);
        vm.prank(merchant);
        uint256 id = pay.createInvoice(amount, block.timestamp + 1 days, "fuzz");
        vm.prank(payer);
        pay.payInvoice(id);
        vm.prank(merchant);
        pay.withdraw(id);
        assertEq(uint256(pay.getInvoice(id).status), uint256(JozzyPay.Status.SETTLED));
        assertEq(usd8.balanceOf(address(pay)), 0);
    }
}
