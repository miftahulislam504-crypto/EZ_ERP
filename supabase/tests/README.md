# Database tests

`0004_purchase_stock_test.sql` and `0005_sales_payments_test.sql` exercise migrations 0004 and 0005 end to end. Each ends
with the line `ALL TESTS PASSED` and stops at the first failed assertion, naming it. Run 0004's test first on an
empty scratch database, then 0005's on the same one. The 0004 test compares totals across the whole database, so it has
to run before any other test adds data; the 0005 test uses its own users and company and works either way.

It needs a scratch database, not your real project, because it creates users, a company and documents.

## Plain PostgreSQL 15 or newer

```
createdb ezerp_test
psql -d ezerp_test -v ON_ERROR_STOP=1 -f supabase/tests/local_supabase_stubs.sql
psql -d ezerp_test -v ON_ERROR_STOP=1 -f supabase/migrations/0001_core.sql
psql -d ezerp_test -v ON_ERROR_STOP=1 -f supabase/migrations/0002_masters.sql
psql -d ezerp_test -v ON_ERROR_STOP=1 -f supabase/migrations/0003_finance.sql
psql -d ezerp_test -v ON_ERROR_STOP=1 -f supabase/migrations/0004_purchase_stock.sql
psql -d ezerp_test -v ON_ERROR_STOP=1 -f supabase/migrations/0005_sales_payments.sql
psql -d ezerp_test -f supabase/tests/0004_purchase_stock_test.sql
psql -d ezerp_test -f supabase/tests/0005_sales_payments_test.sql
```

`local_supabase_stubs.sql` creates the small parts of Supabase the migrations rely on: the `anon`, `authenticated` and
`service_role` roles, `auth.users`, `auth.uid()`, the storage tables and the realtime publication. Skip it if you run
the tests against a local Supabase started with `supabase start`, which already has them.

## What the 0004 test covers

- Requisition submitted by an employee, approval by the owner, visibility rules between roles
- Purchase order raised from the requisition, totals with discount and tax, approval
- Partial goods receipts by a store manager, over-receipt blocked, order status Partial then Received
- Direct receipt without an order and the weighted average cost
- Supplier bill matched to receipt lines with a price difference, a service line and input tax, duplicate supplier
  invoice number blocked, over-billing blocked
- The accounting entries of receipts and bills
- Cancelling a bill, then the receipt, with stock and ledger reversal; a billed receipt cannot be cancelled
- Stock adjustments: reason rules, cost required for additions, approval, posting, insufficient stock
- Immutability of stock movements and posted documents, with and without row level security
- Permission checks and cost hiding for roles without financial data
- Invariants: stock balances equal movement sums, Inventory ledger equals stock value, the books balance

## What the 0005 test covers

- Quotation lifecycle: draft, sent, declined needs a reason, reopened, accepted; converted into a sales order
- Sales order approval by a sales manager, not by an employee; partial invoicing with the order moving to Partial and
  Invoiced; over-invoicing blocked; an order with invoices cannot be cancelled, only closed
- Invoice posting: receivable, revenue, output tax, stock issued at average cost, cost of goods sold
- Credit limit refusal, and the override recorded on the invoice
- Opening balances as invoices and bills: numbering, due dates, equity entry, duplicate reference, permissions,
  cancelling, and a profile balance moving into the books
- Receipts: allocation to several invoices, advance left over, over-allocation and wrong-customer errors, applying an
  advance later, unapplying, cancelling a payment whose allocations changed afterwards, simple cancellation
- Supplier bills and payments mirror the same rules; a bill or invoice with payments cannot be cancelled
- Aging buckets today and as of a past date, statements with an opening row, customer and supplier summaries
- Cancelling an invoice returns stock exactly, including a sale that emptied a stock with a non-terminating average
  cost (the case that would drift by cents)
- Invariants: receivable and payable ledger accounts equal the open documents, advance accounts equal unapplied
  payments, Inventory ledger equals total stock value
- Posted payments and allocations cannot be edited or deleted; visibility by role
