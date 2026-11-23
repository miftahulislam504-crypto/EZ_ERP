# EZ ERP build progress

Last updated at: Phase 1, Step 1D-2 (Sales and payments).

This file answers two questions: what is finished, and what is left. The per-feature detail for every item in the
product plan is in `docs/FEATURE_TRACKER.md`. Design decisions are in `docs/ARCHITECTURE.md`.

## Where we are

| Step | Scope | Status |
| --- | --- | --- |
| 1A Foundation | Sign in, company setup, roles and permissions, users, audit log, notifications, shell, design system, CRUD engine | Done |
| 1B Masters | Customers, suppliers, products and services, warehouses, units, categories, tax rates, numbering | Done |
| 1C Finance core | Chart of accounts, vouchers with posting and reversal, cash and bank, income and expense, ledgers | Done |
| 1D-1 Purchase and stock | Requisition to supplier bill, stock ledger, adjustments, accounting for all of them | Done |
| 1D-2 Sales and payments | Quotation to invoice, receipts and supplier payments, opening balances, aging, statements | Done (this build) |
| 1E Release | Approvals inbox, notification events and push, reports, dashboard figures, search, PDF output, release | Next |
| Phase 2 | Operational ERP (advanced accounting, multi-branch, projects, assets, documents, POS and Workforce integration) | Planned |
| Phase 3 | Enterprise features (multi-company, CRM, service, workflow builder, scheduled reports) | Planned |
| Phase 4 | Intelligence and automation | Planned |

By feature rows in the tracker (a count of items, not of effort): 156 rows in total. 68 are done, 18 are still to come
in Phase 1 (all of them in step 1E, including the notification events row that is generated as modules ship), and 70
belong to later phases. Of the 85 rows marked Phase 1, 68 are done.

## Done in step 1D-2

Database (migration `0005_sales_payments.sql`, tested; no earlier migration was changed):

- Quotations, sales orders and sales invoices on the shared document tables, with their own workflow functions so the
  purchase functions were not touched
- Quotation: draft, sent, accepted or declined (reason required), reopen to edit, expired shown when the valid-until
  date passes. Converted into a sales order, which returns the quotation to Accepted if the order is removed
- Sales order: approval, partial invoicing (an invoice cannot exceed what is left on the order, drafts count), status
  follows its posted invoices (Partial, Invoiced), close the rest
- Invoice posting: Dr Accounts receivable, Cr Sales revenue (or the income account chosen on a line) and Output tax
  payable; stock issued at weighted average cost with Dr Cost of goods sold, Cr Inventory; refused if stock is short
- Customer credit limit checked when an invoice is posted (open invoices less unapplied receipts plus this invoice).
  Sales approvers can post anyway after a confirmation and the override is recorded on the invoice
- Cancelling a posted invoice reverses the entry and returns stock at exactly the value it left at, including large
  sales that emptied a stock with a non-terminating average cost
- Opening balances entered as posted opening invoices and bills with the original date, due date and number, against
  Opening balance equity (your decision 2). They age and are paid like any document
- Receipts and supplier payments with allocation to several invoices or bills, partial payments, advances held on
  Customer advances and Advances to suppliers, applying an advance later, unapplying, and cancelling (a trigger stops
  cancelling an invoice or bill that has payments applied)
- Open amounts are computed from documents and allocations (views `document_balances` and `payment_balances`)
- Aging by days past due with an as-of date, party statements with a running balance and brought-forward balance,
  customer and supplier summaries, order progress, and a control check of the ledger accounts against open documents
- Numbering for receipts (RCT), supplier payments (SPY), opening invoices (OINV) and opening bills (OBILL)
- Test script `supabase/tests/0005_sales_payments_test.sql`: about 120 checks and 45 expected-error checks

Screens (Flutter, English UI):

- Sales: Quotations, Sales orders, Sales invoices, each with a list, summary cards, filters and search, a form and a
  detail page, reusing the purchase document screens. Invoice lists add a Balance column and Paid, Partial and Overdue
  status, with Unpaid and Overdue filters; bills got the same
- Forms: customer, prices from the item, income account for services, stock on hand shown against the quantity sold,
  credit limit and room left shown before posting, due date from the customer's payment terms
- Detail pages: Mark as sent, Customer accepted or declined, Create sales order, Create invoice, Approve and post,
  Record receipt or payment, payments applied, paid and balance due, opening balance and credit override notices
- Receivables and Payables: aging by customer or supplier, totals, advances, a notice if a control account ever
  disagrees, and the list of receipts or payments
- Record receipt or payment form: allocates oldest due date first, adjustable per document, shows what stays as an
  advance. Payment detail page: applied documents, apply an advance, unapply, cancel
- Customer and supplier profile pages: outstanding, overdue, advance, credit available, documents (with an open-only
  switch), payments, statement with date range, and details. Rows in the Customers and Suppliers lists open the profile
- Add opening balance form from the Receivables and Payables screens and from a profile
- Dart tests for allocation, aging buckets and payment status (21 cases run), and for the new document types

## Done in step 1D-1

Database (migration `0004_purchase_stock.sql`, tested):

- Shared document tables for purchase now and sales in 1D-2, with server-side totals, tax and discount
- Requisition, approval, purchase order, approval, goods receipt, supplier bill, with submit, approve, reject, cancel,
  delete draft and close order
- Requisition status follows its orders (Ordered, back to Approved); order status follows its receipts (Partial,
  Received)
- Three-way matching: receipts limited by the order, bills limited by what was received, one supplier invoice number
  per supplier, stock items billed only from posted receipts, services billed with an expense account
- Stock ledger that cannot be edited, warehouse balances with weighted average cost, no negative stock, reversal at
  the original cost
- Stock adjustments with reasons (opening stock, count correction, damaged, expired, lost, internal issue), approval
  and posting
- Accounting: receipt (Dr Inventory, Cr Goods received not billed), bill (clears that account, price variance, input
  tax, Cr Accounts payable), adjustments, and reversals of all of them
- Three new system accounts added to every company: 2150, 5150, 5200
- Cost and value hidden from roles without financial data access
- Notifications for approvals, goods received, bills due and adjustments, with deep links
- Test script with about 100 checks, including the checks that stock balances equal the movement ledger and that the
  Inventory ledger account equals total stock value

Screens (Flutter, English UI):

- Purchase: Requisitions, Purchase orders, Goods receipts, Supplier bills. Each has a list with summary cards, filter
  tabs and search; a form; and a detail page with status actions, linked documents and attachments
- Convert a requisition to an order, receive goods against an order, create a bill from a receipt or from the order
- Order progress per line (ordered, received, billed)
- Stock: Stock overview (value, low stock, out of stock, per warehouse), item stock card with running balance and
  links back to the source document, Stock adjustments (list, form, detail)
- Last purchase price pre-fills order lines

## Left to do

### Step 1E: Release

- One approvals inbox for requisitions, orders, bills, adjustments, vouchers and expenses
- Approval limit by amount (single step; multi-step is Phase 2)
- Notification events for low stock, overdue invoices and due bills, and payment reminders to customers; push
  notifications (needs a Firebase project)
- Basic reports: Profit and Loss, Balance Sheet, Trial Balance, General Ledger, receivables, payables, sales,
  purchase, stock valuation and movement, with date, branch and warehouse filters and drill-down
- Dashboard figures (sales, income, expense, receivable, payable, stock value, pending approvals) and trend charts
- Global record search; quick actions
- PDF output for quotations, sales orders, invoices, purchase orders, goods receipts and bills, and customer and
  supplier statements (voucher PDF already exists)
- Phase 1 release and the full project zip

### Later phases (from the plan)

- Phase 2: advanced accounting and bank reconciliation, budgets, multi-branch, stock transfer and stock count, batch,
  serial and expiry, projects and tasks, assets, document management, purchase and sales returns, supplier quotation
  comparison, EZ POS and EZ Workforce integration
- Phase 3: multi-company and consolidation, CRM pipeline, service and maintenance, workflow builder, custom fields,
  scheduled reports, EZ Menu integration
- Phase 4: KPI dashboards, forecasting, reorder recommendation, unusual transaction alerts, automation, natural
  language queries

## Decisions you confirmed

1. The six decisions of step 1D-1 stand: weighted average cost with no negative stock, supplier payment together with
   customer receipts, receipts accounted when posted, posted documents cancelled rather than edited, receipts limited to
   what was ordered, four decimals on unit prices.
2. Opening balances are entered as invoices and bills. Done in this step.

## Decisions made in this step (tell me if you want any changed)

1. Aging is counted from the due date. The buckets are Not yet due, 1 to 30, 31 to 60, 61 to 90 and Over 90 days past
   due. The plan's 0 to 30 bucket is split into Not yet due and 1 to 30, because a document that is not yet due is
   not late. Advances that are not applied are shown next to the dues, not netted into the buckets.
2. The credit limit is a block at posting, not at order time. Someone with sales approval can post anyway after a
   confirmation, and the invoice keeps a note that the limit was exceeded. Limits on orders and approval of credit
   limit exceptions by a second person come with the approval rules in step 1E.
3. An invoice follows the same path as a bill: submit, approve, post, or approve and post in one step for someone with
   sales approval. Posting needs sales approval, because it moves stock and the books.
4. Payments post the moment they are recorded. A customer receipt can be recorded by finance or by a sales approver;
   a supplier payment needs finance. Cancelling a payment or unapplying an amount needs finance approval. Approval of
   large supplier payments by amount comes in step 1E.
5. An invoice or bill with payments applied cannot be cancelled. Cancel or unapply the payments first.
6. A quotation shows Expired after its valid-until date but can still be converted. Expiry is a display, not a block.
7. Stock is issued by the invoice. There is no delivery challan in Phase 1 (it is in Phase 2), so goods leave stock
   when the invoice is posted.
8. The old opening receivable and payable fields were taken off the customer and supplier forms. A value already stored
   there is not lost: the profile shows a notice, and entering it as an opening invoice or bill reduces the stored
   figure so it is never counted twice.
9. A manual journal posted straight to Accounts receivable or Accounts payable does not appear in aging. The Receivables
   and Payables screens show a notice when the ledger and the open documents disagree.

## Questions for you

- Should customer receipts be allowed to carry withholding tax (AIT or VDS deducted by the customer)? Today a receipt
  is the cash actually received, and any deduction would be a separate adjustment. If you need it as a field on the
  receipt, it is a small addition.
- Do you want credit limit exceptions to need approval from someone other than the person posting? That fits the
  approval rules in step 1E.

## Verification status

- Migration 0005 was applied to PostgreSQL 16 on top of 0001 to 0004. Its test script passes, and the 0004 test still
  passes on the same database (`supabase/tests/`). The 0005 test checks that the Accounts receivable, Accounts
  payable, Customer advances and Advances to suppliers ledger accounts equal the open documents and unapplied
  payments, and that the Inventory account equals total stock value.
- Flutter code has not been compiled, because no Flutter SDK was available. What was done instead: every Dart file
  was parsed with the Dart SDK; the Dart analyzer was run over the whole project and compared with the previous
  upload, which showed no new errors apart from the Flutter and package imports it cannot resolve; the analyzer was
  confirmed to catch wrong parameter names and missing arguments on the project's own widgets; and the new allocation,
  aging and payment-status helpers were run (21 cases pass). Run `flutter analyze` and `flutter test` first and send
  me anything they report.

## How to apply this build

1. Run `supabase/migrations/0005_sales_payments.sql` in the Supabase SQL editor (after 0001 to 0004).
2. `flutter pub get`, then `flutter analyze` and `flutter test`.
3. Try the sales flow: make sure you have a customer, a stock-tracked product with stock, and a warehouse. Create a
   quotation, send it, mark it accepted, create the sales order, approve it, create the invoice, post it, then record a
   receipt from the invoice page. Open Receivables to see aging, and the customer's profile to see the statement.
4. Try opening balances: Receivables, then Add opening balance, enter an old unpaid invoice with its original date,
   and check it appears in the right aging column.
5. Try the supplier side: post a bill, then Record payment from the bill page, and open Payables.
