# EZ ERP

Central business operating system for Android, iOS and Web. One Flutter codebase, Supabase backend.

This archive is the Phase 1, Step 1C build: platform foundation, master data and the finance core. See `docs/FEATURE_TRACKER.md` for the
status of every feature in the product plan and `docs/ARCHITECTURE.md` for design decisions.

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
- Customers and suppliers (groups, credit terms, addresses, opening balances, automatic codes)
- Products and services (SKU, barcode, category, brand, unit, pricing, tax rate, stock levels, images)
- Warehouses, with a default warehouse
- Finance: chart of accounts with balances, cash, bank and mobile wallet accounts, vouchers (payment, receipt,
  transfer, journal) with submit, approve, reject, post and reverse, PDF print with amount in words, income and
  expense with request and approval, cashbook, bankbook and account ledger, bill photos and attachments
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

2. Create the database. Run the files in `supabase/migrations/` in order (0001, 0002, then 0003), either by pasting each
   into the Supabase SQL editor or with the CLI: `supabase link --project-ref <ref>` then `supabase db push`.
   If you already applied earlier files, run only the new ones. 0002 adds a default warehouse and 0003 adds the
   chart of accounts and a cash account to existing companies.

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

- The database migration was applied to PostgreSQL 16 and exercised with test users: seeding, row level security,
  owner protection, invitation claiming and document numbering all behaved as designed.
- The Flutter code was written without access to the Flutter SDK, so it has not been compiled yet. Run
  `flutter analyze` first and report anything it flags; fixes are quick.
