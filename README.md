# EZ ERP

Central business operating system for Android, iOS and Web. One Flutter codebase, Supabase backend.

This archive is the Phase 1, Step 1D-2 build: platform foundation, master data, the finance core, purchase and stock,
and sales and payments.
See `progress.md` for what is done and what remains, `docs/FEATURE_TRACKER.md` for the status of every feature in the
product plan and `docs/ARCHITECTURE.md` for design decisions.

## What is in this build

- Email sign in, registration, password reset
- Company onboarding with seeded defaults (head office, 11 roles, units, payment methods, numbering rules)
- Roles and permissions (View, Create, Edit, Delete, Approve, Export per area), invitations, member management
- Organization, branch and department settings, company logo upload
- Audit log, live notifications, account and session management
- Responsive shell: sidebar and top bar on wide screens, bottom navigation on phones
- Dashboard frame with quick actions and setup checklist
- Navigation map for every module in the plan; unbuilt modules open a roadmap page
- Config-driven CRUD engine used by all master-data screens
- Customers and suppliers (groups, credit terms, addresses, automatic codes), each with a profile page showing dues,
  overdue amounts, advances, credit available, documents, payments, statement and details
- Products and services (SKU, barcode, category, brand, unit, pricing, tax rate, stock levels, images)
- Warehouses, with a default warehouse
- Finance: chart of accounts with balances, cash, bank and mobile wallet accounts, vouchers (payment, receipt,
  transfer, journal) with submit, approve, reject, post and reverse, PDF print with amount in words, income and
  expense with request and approval, cashbook, bankbook and account ledger, bill photos and attachments
- Purchase: requisitions, purchase orders, goods receipts and supplier bills with approval, linked documents, order
  progress (ordered, received, billed), three-way matching, price variance and accounting entries
- Stock: movement ledger, warehouse balances at weighted average cost, stock overview with low and out of stock
  warnings, item stock cards with running balance, stock adjustments (opening stock, count correction, damaged,
  expired, lost, internal issue) with approval and accounting
- Sales: quotations (send, accepted or declined, expiry), sales orders with approval, and invoices that issue stock at
  average cost, book the cost of goods sold and check the customer's credit limit; convert a quotation to an order and
  invoice an order in full or in parts; stock availability shown while selling
- Receipts from customers and payments to suppliers with allocation to several invoices or bills, partial payments,
  advances held and applied later, unapply and cancel, with the accounting entries
- Receivables and Payables screens with aging (not yet due, 1 to 30, 31 to 60, 61 to 90, over 90 days past due),
  advances, drill-down to the party, and a notice if the ledger control account ever disagrees with the open documents
- Opening balances entered as opening invoices and bills with their original dates, so they age like any document
- Business settings: units, product categories, brands, customer groups, supplier categories, payment methods,
  document categories, tax rates and document numbering rules

## Requirements

- Flutter 3.22 or newer (stable channel), Dart 3.3 or newer
- A Supabase project (free tier is enough to start)

## Setup

1. Generate the platform folders. Run inside this directory; existing files in `lib/` are kept.

   ```
   flutter create --platforms=android,ios,web --org com.ezerp --project-name ez_erp .
   flutter pub get
   ```

2. Create the database. Run the files in `supabase/migrations/` in order (0001, 0002, 0003, 0004, then 0005), either by pasting each
   into the Supabase SQL editor or with the CLI: `supabase link --project-ref <ref>` then `supabase db push`.
   If you already applied earlier files, run only the new ones. 0002 adds a default warehouse, 0003 adds the
   chart of accounts and a cash account to existing companies, 0004 adds three system accounts (Goods received not
   billed, Purchase price variance, Stock adjustments and write-offs) to existing companies, and 0005 adds numbering for
   receipts, supplier payments and opening balances.

3. In Supabase, Authentication settings:
   - For quick local testing you may turn off "Confirm email". Keep it on for production.
   - Add your web origin and mobile deep links to the redirect URL allow list.

4. Run the app with your project values (Project Settings, API):

   ```
   flutter run -d chrome \
     --dart-define=SUPABASE_URL=https://your-project.supabase.co \
     --dart-define=SUPABASE_ANON_KEY=your-anon-key
   ```

   The anon key is safe to ship; all data access is enforced by row level security in the database.

5. Register, then complete the two-step company setup. You become the Owner.

## Camera and printing permissions

After `flutter create`, add these keys to `ios/Runner/Info.plist` so phones can photograph bills and choose files:

```
<key>NSCameraUsageDescription</key>
<string>Take photos of bills and receipts to attach to records.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>Choose bills and receipts to attach to records.</string>
```

Android needs no extra setting. PDF printing fetches fonts on first use, so the first print needs a connection.

## Inviting colleagues

Settings, Users and roles, Invitations. The invited person registers or signs in with the same email address and
joins the company automatically with the chosen role. Email delivery of invitations arrives in Phase 2.

## Quality checks

```
flutter analyze
flutter test
```

## Status of verification

- The database migrations were applied to PostgreSQL 16 and exercised with test users: seeding, row level security,
  owner protection, invitation claiming and document numbering all behaved as designed.
- Migration 0004 has an automated test in `supabase/tests/0004_purchase_stock_test.sql` (see the folder's README). It
  walks a requisition through order, partial receipts, a bill with a price difference, reversals, adjustments and
  permission checks, and verifies that stock balances equal the movement ledger and that the Inventory ledger account
  equals total stock value.
- Migration 0005 has an automated test in `supabase/tests/0005_sales_payments_test.sql`. It covers the sales flow from
  quotation to invoice, posting and stock, credit limits, opening balances, receipts and payments with allocation,
  advances and reversals, aging and statements, and checks that the receivable, payable and advance accounts equal the
  open documents behind them.
- The Flutter code was written without access to the Flutter SDK, so it has not been compiled yet. Every Dart file
  was parsed with the Dart SDK and the pure calculation helpers were run in the Dart VM, but type checking against
  the Flutter and package APIs could not be done. Run `flutter analyze` first and report anything it flags; fixes
  are quick.
