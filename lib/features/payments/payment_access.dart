import '../../core/permissions/permissions.dart';
import 'payment_models.dart';

/// Who may see the receivable or payable books of one side.
bool canViewLedger(PermissionSet p, LedgerSide side) => p.canView(Modules.finance) || p.canView(side.module);

/// Who may record a receipt or payment, or apply an advance. Customer receipts
/// can also be recorded by whoever may approve sales; supplier payments need finance.
bool canRecordPayment(PermissionSet p, LedgerSide side) =>
    p.can(Modules.finance, PermAction.create) || (side.isReceivable && p.can(Modules.sales, PermAction.approve));

/// Who may cancel a payment or take an amount off a document.
bool canReversePayment(PermissionSet p) => p.can(Modules.finance, PermAction.approve);

/// Who may enter opening balances.
bool canEnterOpening(PermissionSet p) => p.can(Modules.finance, PermAction.create);
