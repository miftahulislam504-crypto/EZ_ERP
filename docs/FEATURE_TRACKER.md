# Feature tracker

Every feature in the EZ ERP plan is listed here with its phase. Status values: Done, Next (Phase 1, upcoming step),
or the phase number it ships in. Nothing is removed; items only move between phases if you decide to.

## Phase 1 build steps

| Step | Scope | Status |
| --- | --- | --- |
| 1A Foundation | Auth, onboarding, roles and permissions, organization, branches, departments, users, audit log, notification center, responsive shell, design system, CRUD engine, core migration | Done |
| 1B Masters | Customers, suppliers, lookups (units, categories, brands, payment methods), numbering rules, products and services, warehouses, tax rates | Done |
| 1C Finance core | Chart of accounts, journal, payment, receipt and contra vouchers with posting, cash and bank accounts, income and expense, cashbook and bankbook | Done |
| 1D-1 Purchase and stock | Requisitions, purchase orders, goods receipts, supplier bills with three-way matching, stock ledger, warehouse balances, valuation, stock adjustments, accounting for receipts, bills and adjustments | Done |
| 1D-2 Sales and payments | Quotations, sales orders, invoices, receipts and supplier payments with allocation, receivable and payable aging, statements, customer and supplier transaction history, opening balances as invoices and bills | Done |
| 1E Release | Approvals inbox, notification events and push, basic reports, dashboard data, record search, PDF output, Phase 1 release | Next |

A zip of the full project is delivered at the end of every phase, and as a checkpoint after each step.

## 3. Users, roles and access

| Feature | Phase | Status |
| --- | --- | --- |
| 11 default roles (Owner, Director, General Manager, Accounts Manager, Accountant, Purchase, Sales, Inventory, Project, Department Head, Employee, Auditor) | 1 | Done |
| Menus and features shown by role | 1 | Done |
| View, Create, Edit, Delete, Approve, Export permission per area | 1 | Done |
| Branch scoped access | 1 | Done (stored, applied to pickers; applied to data as branch-aware tables arrive) |
| Warehouse, department and project scoped access | 2 | Planned |
| Separate permission for financial figures | 1 | Done (permission exists; enforced in queries as finance data arrives) |
| Higher approval above an amount limit | 1 | Next (1E), advanced rules in Phase 2 |
| Audit log of create, change, approve, cancel | 1 | Done |
| Revoke access when someone leaves | 1 | Done |

## 4. Dashboards

| Feature | Phase | Status |
| --- | --- | --- |
| Owner dashboard frame, period filter, branch filter | 1 | Done |
| Cash and bank balance figure | 1 | Done |
| Sales, income, expense, receivable, payable, stock value, pending approvals figures | 1 | Next (1E) |
| Monthly and yearly trend charts | 1 | Next (1E) |
| Branch performance, running projects, business targets versus actual | 2 and 3 | Planned |
| Department dashboards | 2 | Planned |
| Add, remove and reorder widgets | 2 | Planned |
| Dashboard setup checklist | 1 | Done |

## 5. Finance and accounting

| Feature | Phase | Status |
| --- | --- | --- |
| Chart of accounts with parent accounts, codes, default categories, balances | 1 | Done |
| Branch and department based account classification | 2 | Planned |
| Journal, payment, receipt, contra vouchers; auto numbers; statuses Draft to Posted; attachments; print and PDF with amount in words; controlled reversal | 1 | Done |
| Debit note and credit note | 2 | Planned |
| Expense request, approval, payment, cancellation, bill upload, income entries, by cash or bank | 1 | Done |
| Daily to yearly income and expense summaries | 1 | Next (1E, reports) |
| Recurring expenses | 2 | Planned (automation in Phase 4) |
| Budget versus actual, limit alerts | 2 | Planned |
| Accounts receivable: dues, partial payments, overdue days, statement, advance and credit balance, aging | 1 | Done (1D-2) |
| Payment reminders to customers | 2 | Planned |
| Accounts payable: bills posted to the ledger with supplier and due date | 1 | Done (1D-1) |
| Accounts payable: partial payment, statement, advance to supplier, aging | 1 | Done (1D-2) |
| Opening balances entered as posted opening invoices and bills with their original dates, so they age and are paid like any document | 1 | Done (1D-2) |
| Receipts and supplier payments with allocation to several documents, applying an advance later, unapplying and reversal | 1 | Done (1D-2) |
| Receivable and payable control accounts checked against the open documents behind them | 1 | Done (1D-2) |
| Multiple cash, bank and mobile wallet accounts with opening balance, receive, pay, deposit, withdrawal, transfer, cashbook, bankbook | 1 | Done |
| Bank reconciliation, cheque lifecycle, daily cash closing | 2 | Planned |
| Annual and monthly budgets, future cash flow planning | 2 and 4 | Planned |
| Account ledger, cashbook, bankbook with running balance | 1 | Done |
| Reports: Profit and Loss, Balance Sheet, Trial Balance, General Ledger (all accounts), Receivable, Payable, Expense | 1 | Next (1E) |
| Cash Flow Statement, branch-wise and department-wise reports | 2 | Planned |
| Tax and VAT summary, configurable, with no compliance claims | 2 | Planned |

## 6. Purchase and suppliers

| Feature | Phase | Status |
| --- | --- | --- |
| Supplier profile, contact, address, category, trade license, payment terms, opening payable (entered as opening bills) | 1 | Done |
| Supplier documents (attachments on every purchase document) | 1 | Done |
| Supplier dues, advance and payment history | 1 | Done (1D-2) |
| Supplier contracts and files, rating and performance notes | 2 | Planned |
| Requisition, approval, purchase order, goods receipt, bill, verification, stock and account sync | 1 | Done (1D-1) |
| Payment and partial payment of supplier bills | 1 | Done (1D-2) |
| Supplier quotation collection and comparison | 2 | Planned |
| Purchase return, supplier debit and credit adjustment | 2 | Planned |
| Purchase history through linked documents, latest purchase price, open orders and pending approvals on the list screens | 1 | Done (1D-1) |
| Supplier-wise purchase report, approval limit by amount | 1 | Next (1E) |
| Purchase suggestion from reorder level | 2 | Planned (AI recommendation in Phase 4) |

## 7. Sales and customers

| Feature | Phase | Status |
| --- | --- | --- |
| Customer profile for people and companies, billing and shipping address, trade license, group, credit limit, payment terms, opening receivable (entered as opening invoices) | 1 | Done |
| Customer transaction history | 1 | Done (1D-2) |
| Notes, follow-ups and contact records | 2 | Planned |
| Quotation, sales order, approval, invoice, partial payment and due tracking | 1 | Done (1D-2) |
| Customer credit limit checked when an invoice is posted, with the override recorded on the invoice | 1 | Done (1D-2) |
| Partial invoicing of a sales order, with the order following its invoices | 1 | Done (1D-2) |
| Invoice PDF and print | 1 | Next (1E) |
| Invoice email and share | 2 | Planned |
| Delivery challan | 2 | Planned |
| Sales return, credit note, discount approval | 2 | Planned |
| Salesperson-wise sales | 2 | Planned |
| Customer-wise and product-wise sales report | 1 | Next (1E) |
| Lead pipeline: sources, status, follow-up, conversion | 3 | Planned |

## 8. Inventory and warehouses

| Feature | Phase | Status |
| --- | --- | --- |
| Products, services, raw materials, asset items with SKU, barcode, categories, brand, unit, images, pricing, tax rate, reorder level | 1 | Done |
| Variants | 2 | Planned |
| Batch, serial, expiry and warranty tracking | 2 | Planned |
| Multiple warehouses with default warehouse | 1 | Done |
| Warehouse-wise stock quantities | 1 | Done (1D-1) |
| Rack and shelf locations | 2 | Planned |
| Goods receive, stock issue, adjustment, opening stock, damaged, expired and lost stock, movement history, weighted average valuation | 1 | Done (1D-1) |
| Stock issue to customers through invoices | 1 | Done (1D-2) |
| Stock transfer with request, approval, dispatch and receive | 2 | Planned |
| Physical stock count versus system stock | 2 | Planned |
| Low stock and out of stock warnings on the stock screen | 1 | Done (1D-1) |
| Low stock and out of stock notifications | 1 | Next (1E) |
| Expiry, slow-moving, non-moving and overstock alerts | 2 | Planned |
| Stock reports (current, valuation, movement) | 1 | Next (1E) |
| Warehouse comparison, batch and serial reports | 2 | Planned |

## 9. Projects and tasks

| Feature | Phase | Status |
| --- | --- | --- |
| Projects with client, team, dates, status, budget, cost versus estimate, revenue, milestones, documents | 2 | Planned |
| Tasks, subtasks, assignment, priority, reminders, checklist, comments, attachments, dependencies, Kanban, list and calendar views | 2 | Planned |
| Progress, budget consumption, project income and expense, client updates | 2 | Planned |

## 10. HR administration inside ERP

| Feature | Phase | Status |
| --- | --- | --- |
| Departments and department head | 1 | Done |
| Designations, organization chart, directory, approval hierarchy | 2 | Planned |
| Expense claim approval, staff assignment to purchase, sales and projects | 2 | Planned |
| EZ Workforce summary and salary cost summary | 2 | Planned |

## 11. Assets and maintenance

| Feature | Phase | Status |
| --- | --- | --- |
| Asset register, location, custodian, status, documents | 2 | Planned |
| Depreciation methods, schedule, book value, report | 2 | Planned |
| Maintenance schedule, repair requests, cost, history, warranty alerts, transfer and disposal approval | 3 | Planned |

## 12. Service and support

| Feature | Phase | Status |
| --- | --- | --- |
| Service catalogue, tickets, technician assignment, visits, parts, warranty and AMC, complaints, completion, service invoice, resolution report | 3 | Planned |

## 13. Documents

| Feature | Phase | Status |
| --- | --- | --- |
| File attachments on records (storage, tenant isolation, metadata table) | 1 | Done (storage layer), screens arrive with each module |
| Central folders, search, preview, version dates, role-based access, expiry reminders | 2 | Planned |

## 14. Workflow and approvals

| Feature | Phase | Status |
| --- | --- | --- |
| Single-step approval for voucher and expense (approve, reject with reason) | 1 | Done |
| Single-step approval for requisition, order, payment with one shared Approvals inbox | 1 | Next (1E) |
| Multi-step approval, amount limits, department approvers, reminders, substitute approver | 2 | Planned |
| Custom workflow builder | 3 | Planned |
| Workflow automation rules | 4 | Planned |

## 15. Branches and companies

| Feature | Phase | Status |
| --- | --- | --- |
| Branch setup, head office, company switcher | 1 | Done |
| Branch-wise sales, purchase, expense, warehouse, budget, user access, stock transfer, head office dashboard | 2 | Planned |
| Multiple legal entities, consolidated reports, inter-company transactions | 3 | Planned |

## 16. Notifications

| Feature | Phase | Status |
| --- | --- | --- |
| Notification center with live in-app updates, read state | 1 | Done |
| Notifications for voucher and expense submission, approval, rejection and payment | 1 | Done |
| Notifications for requisition, order, bill and stock adjustment approvals, goods received, bills due | 1 | Done (1D-1) |
| Events: approvals, dues, overdue invoices, stock, purchase orders, deadlines, warranty, document expiry, budget | 1 to 3 | Generated as each module ships |
| Push notifications on mobile | 1 | Next (1E, needs a Firebase project) |
| Email notifications | 2 | Planned |
| SMS and WhatsApp through connected services | 3 | Planned |
| Per-user notification preferences | 2 | Planned |
| Deep link from notification to the record | 1 | Done for vouchers, expenses, purchase documents and stock adjustments; sales records as they ship |

## 17. Reports and business intelligence

| Feature | Phase | Status |
| --- | --- | --- |
| Core financial, sales, purchase and inventory reports with date range, branch and warehouse filters, drill-down | 1 | Next (1E) |
| PDF and CSV export, print | 1 | Next (1E) |
| Excel export, saved report views, sharing with users | 2 | Planned |
| Project and operations reports, department performance | 2 | Planned |
| Scheduled report delivery | 3 | Planned |

## 18. Mobile experience

| Feature | Phase | Status |
| --- | --- | --- |
| Bottom navigation: Home, Modules, Approvals, Alerts, More | 1 | Done |
| Role-based menus, large actions, confirmation before important actions | 1 | Done |
| Dashboard, search, view documents, record payment, expense request, approvals, stock check | 1 | Next (1B to 1E) |
| Photograph a bill or receipt and attach it | 1 | Done (vouchers and expenses) |
| Barcode and QR scan | 2 | Planned |
| Offline drafts with visible sync state | 2 | Planned |
| Biometric unlock | 2 | Planned |
| Task assignment and project progress on mobile | 2 | Planned |

## 19. Web experience

| Feature | Phase | Status |
| --- | --- | --- |
| Sidebar, top bar with company and branch switcher, search, notifications, profile | 1 | Done |
| Data tables with search, filters, archive | 1 | Done (CRUD engine) |
| Column show and hide, sort, bulk select and actions | 2 | Planned |
| Excel and CSV import and export | 2 | Planned |
| Drag-and-drop upload | 2 | Planned |
| Keyboard-friendly data entry, multi-tab work, right-side quick panel | 2 and 3 | Planned |
| Workflow and permission configuration | 1 and 2 | Permissions done, workflow in 1E and 2 |

## 20. Global search and quick actions

| Feature | Phase | Status |
| --- | --- | --- |
| Search pages and actions (Ctrl K or Cmd K), permission-aware | 1 | Done |
| Search customers, suppliers, products, invoices, vouchers, orders | 1 | Next (1E) |
| Search projects, tasks, employees, assets, tickets, documents | 2 and 3 | Planned |
| Quick actions (invoice, quotation, purchase request, payment, expense, customer, supplier, task, transfer) | 1 | Done (shortcuts), targets arrive with modules; customer, supplier, invoice and receipt targets are live |

## 21. Settings and administration

| Feature | Phase | Status |
| --- | --- | --- |
| Company name, logo, contact, address, business information | 1 | Done |
| Financial year, default currency, date format, time zone | 1 | Done |
| Invoice and voucher numbering rules (prefix, length, next number) | 1 | Done |
| Branch and department setup | 1 | Done |
| Tax rates (configurable, none assumed) | 1 | Done |
| Tax applied on purchase documents (input tax booked on bills) | 1 | Done (1D-1) |
| Tax applied on sales documents, VAT summary reports | 1 and 2 | Next (1D-2), reports in Phase 2 |
| Payment methods, units, brands, product, customer and supplier categories, document categories | 1 | Done |
| Warehouse setup | 1 | Done |
| Approval rules | 1 | Next (1E) |
| Notification rules | 2 | Planned |
| Custom fields | 3 | Planned |
| User invitation, role and permission, audit log | 1 | Done |
| Session management (sign out other devices), password change | 1 | Done |
| Two-factor authentication, login history, data export permission | 2 | Planned |

## 22. Bangladesh-specific

| Feature | Phase | Status |
| --- | --- | --- |
| BDT default currency, other currencies selectable | 1 | Done |
| Lakh and crore number grouping | 1 | Done |
| Division selection; district, upazila and area as text | 1 | Done |
| Full division, district, upazila, area hierarchy dataset | 2 | Planned |
| Local units (Hali, Maund and others) | 1 | Done (seeded) |
| Cash, bank, card, bKash, Nagad, Rocket recorded as payment methods | 1 | Done (seeded), used from 1C |
| Payment gateway integration (bKash, Nagad, Rocket, bank) | 3 | Planned, needs provider agreements |
| Configurable VAT and tax settings and reports | 1 and 2 | Planned, no compliance claims |
| Low-bandwidth friendly screens | 2 | Planned |

## Decision to confirm

The plan lists Bangla and English UI and Bangla print for invoices, challans and vouchers. The instruction for this
build is a fully English UI and UX, so Bangla language support is not in the current scope. Text is kept in one place
per screen so a language layer can be added later without redesign. Tell me if you want Bangla added back as a phase.

## Phase roadmap from the plan

- Phase 1, Core ERP MVP: steps 1A to 1E above.
- Phase 2, Operational ERP: advanced accounting, reconciliation, budgets, multi-branch, advanced approvals, transfers
  and counts, batch, serial and expiry, projects and tasks, assets, documents, advanced reports, EZ POS and basic EZ
  Workforce integration.
- Phase 3, Enterprise: multi-company and consolidation, CRM pipeline, service and maintenance, cost and profit
  centres, inter-company transactions, workflow builder, custom fields and report builder, scheduled reports, EZ Menu
  integration, advanced audit and compliance tools.
- Phase 4, Intelligence: KPI and BI dashboards, forecasting, reorder recommendation, unusual transaction alerts,
  automated recurring entries, workflow automation, AI report summary, natural language business questions,
  predictive insights. AI results stay advisory.

Excluded from the first release as in the plan: full payroll engine, full restaurant ordering, counter POS,
manufacturing planning, supply chain optimization, automated financial decisions, complete tax compliance for every
country, social or chat features.
