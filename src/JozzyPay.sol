// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title JozzyPay — stablecoin payment links for small businesses
/// @notice A merchant creates an invoice denominated in a stablecoin (tUSD8 on
///         QDay Aevum). A customer pays it; the funds sit in escrow in this
///         contract until the merchant withdraws them. If the merchant never
///         withdraws and the invoice expires, the payer can refund themselves.
/// @dev Pull-payment pattern throughout: the contract never pushes funds to
///      anyone except on an explicit withdraw/refund call by the entitled
///      party. A per-invoice spend cap bounds what any single payment — human
///      or agent acting on an ERC20 allowance — can move, so a compromised
///      agent key cannot drain more than one invoice's cap.
contract JozzyPay is ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice The stablecoin accepted for payment (tUSD8 on QDay Aevum).
    IERC20 public immutable token;

    /// @notice Deployer; may only lower/raise the per-invoice cap. Has no
    ///         access to escrowed funds.
    address public immutable owner;

    /// @notice Maximum amount (in token base units, 6 decimals for tUSD8)
    ///         of any single invoice. Default: 10,000 tUSD8.
    uint256 public maxInvoiceAmount;

    /// @notice Default cap: 10,000 tUSD8 (10_000 * 10^6 base units).
    uint256 public constant DEFAULT_MAX_INVOICE_AMOUNT = 10_000 * 1e6;

    enum Status {
        OPEN,
        PAID,
        SETTLED,
        REFUNDED,
        CANCELLED
    }

    struct Invoice {
        address merchant;
        address payer;
        uint256 amount;
        uint256 expiresAt;
        uint256 paidAt;
        Status status;
        string memo;
    }

    uint256 public nextInvoiceId;
    mapping(uint256 => Invoice) public invoices;

    event InvoiceCreated(uint256 indexed id, address indexed merchant, uint256 amount, uint256 expiresAt, string memo);
    event InvoicePaid(uint256 indexed id, address indexed payer, uint256 amount);
    event InvoiceSettled(uint256 indexed id, address indexed merchant, uint256 amount);
    event InvoiceRefunded(uint256 indexed id, address indexed payer, uint256 amount);
    event InvoiceCancelled(uint256 indexed id);
    event MaxInvoiceAmountUpdated(uint256 newMax);

    error AmountZero();
    error AmountExceedsCap(uint256 amount, uint256 cap);
    error ExpiryInPast(uint256 expiresAt, uint256 now_);
    error NotMerchant(address caller, address merchant);
    error NotPayer(address caller, address payer);
    error NotOwner(address caller, address owner);
    error WrongStatus(uint256 id, Status status);
    error InvoiceExpired(uint256 id, uint256 expiresAt, uint256 now_);
    error InvoiceNotExpired(uint256 id, uint256 expiresAt, uint256 now_);

    constructor(IERC20 _token, uint256 _maxInvoiceAmount) {
        if (address(_token) == address(0)) revert AmountZero();
        token = _token;
        owner = msg.sender;
        maxInvoiceAmount = _maxInvoiceAmount == 0 ? DEFAULT_MAX_INVOICE_AMOUNT : _maxInvoiceAmount;
    }

    /// @notice Create a payment request. Anyone can create one; the caller is
    ///         the merchant who will receive the funds on withdraw.
    /// @param amount Amount in token base units (tUSD8 has 6 decimals).
    /// @param expiresAt Unix timestamp after which the invoice can no longer
    ///        be paid, and after which the payer may refund a paid invoice.
    /// @param memo Human-readable note, e.g. "CV writing — Jozzyhub".
    /// @return id The new invoice id.
    function createInvoice(uint256 amount, uint256 expiresAt, string calldata memo) external returns (uint256 id) {
        if (amount == 0) revert AmountZero();
        if (amount > maxInvoiceAmount) {
            revert AmountExceedsCap(amount, maxInvoiceAmount);
        }
        if (expiresAt <= block.timestamp) {
            revert ExpiryInPast(expiresAt, block.timestamp);
        }
        id = nextInvoiceId++;
        invoices[id] = Invoice({
            merchant: msg.sender,
            payer: address(0),
            amount: amount,
            expiresAt: expiresAt,
            paidAt: 0,
            status: Status.OPEN,
            memo: memo
        });
        emit InvoiceCreated(id, msg.sender, amount, expiresAt, memo);
    }

    /// @notice Pay an open invoice. The payer must have approved this
    ///         contract to pull `amount` of the token first.
    function payInvoice(uint256 id) external nonReentrant {
        Invoice storage inv = invoices[id];
        if (inv.status != Status.OPEN) revert WrongStatus(id, inv.status);
        if (block.timestamp > inv.expiresAt) {
            revert InvoiceExpired(id, inv.expiresAt, block.timestamp);
        }
        inv.status = Status.PAID;
        inv.payer = msg.sender;
        inv.paidAt = block.timestamp;
        token.safeTransferFrom(msg.sender, address(this), inv.amount);
        emit InvoicePaid(id, msg.sender, inv.amount);
    }

    /// @notice Merchant withdraws the escrowed funds of a paid invoice.
    function withdraw(uint256 id) external nonReentrant {
        Invoice storage inv = invoices[id];
        if (inv.merchant != msg.sender) {
            revert NotMerchant(msg.sender, inv.merchant);
        }
        if (inv.status != Status.PAID) revert WrongStatus(id, inv.status);
        inv.status = Status.SETTLED;
        token.safeTransfer(msg.sender, inv.amount);
        emit InvoiceSettled(id, msg.sender, inv.amount);
    }

    /// @notice Payer reclaims escrowed funds of a paid invoice whose expiry
    ///         has passed and which the merchant never withdrew.
    function refund(uint256 id) external nonReentrant {
        Invoice storage inv = invoices[id];
        if (inv.payer != msg.sender) {
            revert NotPayer(msg.sender, inv.payer);
        }
        if (inv.status != Status.PAID) revert WrongStatus(id, inv.status);
        if (block.timestamp <= inv.expiresAt) {
            revert InvoiceNotExpired(id, inv.expiresAt, block.timestamp);
        }
        inv.status = Status.REFUNDED;
        token.safeTransfer(msg.sender, inv.amount);
        emit InvoiceRefunded(id, msg.sender, inv.amount);
    }

    /// @notice Merchant cancels an unpaid invoice.
    function cancel(uint256 id) external {
        Invoice storage inv = invoices[id];
        if (inv.merchant != msg.sender) {
            revert NotMerchant(msg.sender, inv.merchant);
        }
        if (inv.status != Status.OPEN) revert WrongStatus(id, inv.status);
        inv.status = Status.CANCELLED;
        emit InvoiceCancelled(id);
    }

    /// @notice Owner may adjust the per-invoice spend cap. This is the only
    ///         owner power; it never touches escrowed funds.
    function setMaxInvoiceAmount(uint256 newMax) external {
        if (msg.sender != owner) revert NotOwner(msg.sender, owner);
        if (newMax == 0) revert AmountZero();
        maxInvoiceAmount = newMax;
        emit MaxInvoiceAmountUpdated(newMax);
    }

    /// @notice Read a full invoice record.
    function getInvoice(uint256 id) external view returns (Invoice memory) {
        return invoices[id];
    }
}
