\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on

-- Helpers ------------------------------------------------------------
create or replace function public.t_assert(p_ok boolean, p_msg text) returns void language plpgsql as $$
begin if not coalesce(p_ok, false) then raise exception 'ASSERT FAILED: %', p_msg; end if; end $$;

create or replace function public.t_expect_error(p_sql text, p_pattern text) returns void language plpgsql as $$
declare v_msg text;
begin
  begin
    execute p_sql;
  exception when others then
    get stacked diagnostics v_msg = message_text;
    if v_msg ilike '%' || p_pattern || '%' then return; end if;
    raise exception 'ASSERT FAILED: expected error like "%" but got "%" for: %', p_pattern, v_msg, left(p_sql, 120);
  end;
  raise exception 'ASSERT FAILED: expected error like "%" but statement succeeded: %', p_pattern, left(p_sql, 120);
end $$;

-- Net debit balance of a system account (debit minus credit) from posted vouchers.
create or replace function public.t_bal(p_org uuid, p_key text) returns numeric language sql stable security definer set search_path = public as $$
  select coalesce(sum(l.debit - l.credit), 0)
  from voucher_lines l join vouchers v on v.id = l.voucher_id join accounts a on a.id = l.account_id
  where a.org_id = p_org and a.system_key = p_key and v.status = 'posted';
$$;

create or replace function public.t_acct_bal(p_org uuid, p_account uuid) returns numeric language sql stable security definer set search_path = public as $$
  select coalesce(sum(l.debit - l.credit), 0)
  from voucher_lines l join vouchers v on v.id = l.voucher_id
  where l.org_id = p_org and l.account_id = p_account and v.status = 'posted';
$$;

-- Users ---------------------------------------------------------------
insert into auth.users (id, email) values
 ('00000000-0000-0000-0000-000000000501', 'owner.s@t.com'),
 ('00000000-0000-0000-0000-000000000502', 'employee.s@t.com'),
 ('00000000-0000-0000-0000-000000000503', 'accountant.s@t.com'),
 ('00000000-0000-0000-0000-000000000504', 'sales.s@t.com'),
 ('00000000-0000-0000-0000-000000000505', 'buyer.s@t.com'),
 ('00000000-0000-0000-0000-000000000506', 'auditor.s@t.com');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000501', false);
set role authenticated;
select public.create_organization('Test Co') as org \gset
reset role;

select set_config('app.bootstrap', 'on', false);
insert into organization_members (org_id, user_id, role_id)
select :'org', u.id, r.id from (values
  ('00000000-0000-0000-0000-000000000502'::uuid, 'Employee / Staff'),
  ('00000000-0000-0000-0000-000000000503'::uuid, 'Accountant'),
  ('00000000-0000-0000-0000-000000000504'::uuid, 'Sales Manager'),
  ('00000000-0000-0000-0000-000000000505'::uuid, 'Purchase Manager'),
  ('00000000-0000-0000-0000-000000000506'::uuid, 'Auditor / Viewer')) as u(id, role)
join roles r on r.org_id = :'org' and r.name = u.role;
select set_config('app.bootstrap', 'off', false);

-- Master data as owner ---------------------------------------------------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000501', false);
set role authenticated;

insert into parties (org_id, name, is_customer, credit_limit, payment_terms_days) values (:'org', 'Acme Retail', true, 5000, 30) returning id as c1 \gset
insert into parties (org_id, name, is_customer, payment_terms_days, opening_receivable) values (:'org', 'Bravo Stores', true, 0, 500) returning id as c2 \gset
insert into parties (org_id, name, is_customer, credit_limit, payment_terms_days) values (:'org', 'Limit Co', true, 100, 10) returning id as c4 \gset
insert into parties (org_id, name, is_customer, payment_terms_days) values (:'org', 'Spread Ltd', true, 0) returning id as c5 \gset
insert into parties (org_id, name, is_supplier, payment_terms_days) values (:'org', 'Alpha Supplies', true, 15) returning id as s1 \gset
insert into products (org_id, name, item_type, track_inventory) values (:'org', 'Widget', 'product', true) returning id as p1 \gset
insert into products (org_id, name, item_type, track_inventory) values (:'org', 'Gadget', 'product', true) returning id as p2 \gset
insert into products (org_id, name, item_type) values (:'org', 'Delivery', 'service') returning id as p3 \gset
insert into products (org_id, name, item_type, track_inventory) values (:'org', 'Stationery', 'product', false) returning id as p4 \gset
insert into products (org_id, name, item_type, track_inventory) values (:'org', 'Bulk fill', 'product', true) returning id as p5 \gset
insert into tax_rates (org_id, name, rate, applies_to) values (:'org', 'Test VAT 5', 5, 'both') returning id as vat \gset
select id as wh from warehouses where org_id = :'org' and is_default \gset
select id as acc_util from accounts where org_id = :'org' and code = '5320' \gset
select public.create_financial_account(:'org', 'cash', 'Test Cash') as fin_cash \gset
select public.create_financial_account(:'org', 'bank', 'Test Bank', 'Test Bank Ltd') as fin_bank \gset
select account_id as gl_cash from financial_accounts where id = :'fin_cash' \gset
select account_id as gl_bank from financial_accounts where id = :'fin_bank' \gset

-- Opening stock: Widget 100 @ 10, Gadget 50 @ 40, Bulk 1000 @ 0.3333 and 2000 @ 0.3334.
select public.save_stock_adjustment(gen_random_uuid(), :'org', current_date, :'wh', 'opening_stock', null,
  jsonb_build_array(jsonb_build_object('product_id', :'p1', 'quantity_change', 100, 'unit_cost', 10),
                    jsonb_build_object('product_id', :'p2', 'quantity_change', 50, 'unit_cost', 40),
                    jsonb_build_object('product_id', :'p5', 'quantity_change', 1000, 'unit_cost', 0.3333))) as adj1 \gset
select public.submit_stock_adjustment(:'adj1'); select public.approve_stock_adjustment(:'adj1'); select public.post_stock_adjustment(:'adj1');
select public.save_stock_adjustment(gen_random_uuid(), :'org', current_date, :'wh', 'opening_stock', null,
  jsonb_build_array(jsonb_build_object('product_id', :'p5', 'quantity_change', 2000, 'unit_cost', 0.3334))) as adj2 \gset
select public.submit_stock_adjustment(:'adj2'); select public.approve_stock_adjustment(:'adj2'); select public.post_stock_adjustment(:'adj2');

\echo '== 1. numbering seeded for the new records'
select public.t_assert((select count(*) from doc_sequences where org_id = :'org'
  and doc_type in ('opening_invoice', 'opening_bill', 'customer_receipt', 'supplier_payment')) = 4, 'four sequences seeded');

\echo '== 2. quotation lifecycle'
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000502', false);
select public.t_expect_error(format($q$select public.save_sales_document(gen_random_uuid(), %L, 'sales_quotation', %L, current_date, null, null, null, null, null, null, null,
  jsonb_build_array(jsonb_build_object('product_id', %L, 'quantity', 1, 'unit_price', 5)))$q$, :'org', :'c1', :'p1'), 'permission');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000504', false);
select public.t_expect_error(format($q$select public.save_sales_document(gen_random_uuid(), %L, 'sales_quotation', %L, current_date, null, null, null, null, null, null, null,
  jsonb_build_array(jsonb_build_object('product_id', %L, 'quantity', 1, 'unit_price', 5)))$q$, :'org', :'s1', :'p1'), 'valid customer');
select public.t_expect_error(format($q$select public.save_sales_document(gen_random_uuid(), %L, 'sales_quotation', %L, current_date, null, null, null, null, null, null, null,
  jsonb_build_array(jsonb_build_object('product_id', %L, 'quantity', 0, 'unit_price', 5)))$q$, :'org', :'c1', :'p1'), 'quantity');
select public.save_sales_document(gen_random_uuid(), :'org', 'sales_quotation', :'c1', current_date, null, current_date + 15, null, null, 'RFQ-7', 'Initial quote', null,
  jsonb_build_array(
    jsonb_build_object('product_id', :'p1', 'quantity', 10, 'unit_price', 15, 'discount_amount', 10, 'tax_rate_id', :'vat'),
    jsonb_build_object('product_id', :'p3', 'quantity', 1, 'unit_price', 200))) as q1 \gset
select public.t_assert((select subtotal from trade_documents where id = :'q1') = 350, 'quotation subtotal');
select public.t_assert((select discount_total from trade_documents where id = :'q1') = 10, 'quotation discount');
select public.t_assert((select tax_total from trade_documents where id = :'q1') = 7, 'quotation tax');
select public.t_assert((select total from trade_documents where id = :'q1') = 347, 'quotation total');
select public.t_assert((select number from trade_documents where id = :'q1') like 'QUO%' or (select number from trade_documents where id = :'q1') like 'QT%', 'quotation number prefix');
select public.t_assert((select status from trade_documents where id = :'q1') = 'draft', 'quotation is a draft');
select public.mark_quotation_sent(:'q1');
select public.t_assert((select status from trade_documents where id = :'q1') = 'sent', 'quotation sent');
select public.t_expect_error(format($q$select public.set_quotation_outcome(%L, 'rejected', null)$q$, :'q1'), 'why the customer declined');
select public.reopen_quotation(:'q1');
select public.t_assert((select status from trade_documents where id = :'q1') = 'draft', 'quotation reopened');
select public.mark_quotation_sent(:'q1');
select public.set_quotation_outcome(:'q1', 'accepted');
select public.t_assert((select status from trade_documents where id = :'q1') = 'accepted', 'quotation accepted');
select id as ql1 from trade_document_lines where document_id = :'q1' and line_no = 1 \gset
select id as ql2 from trade_document_lines where document_id = :'q1' and line_no = 2 \gset

\echo '== 3. sales order from the quotation, with approval'
select public.t_expect_error(format($q$select public.save_sales_document(gen_random_uuid(), %L, 'sales_order', %L, current_date, null, null, null, %L, null, null, %L,
  jsonb_build_array(jsonb_build_object('product_id', %L, 'quantity', 1, 'unit_price', 5)))$q$, :'org', :'c2', :'wh', :'q1', :'p1'), 'must match');
select public.save_sales_document(gen_random_uuid(), :'org', 'sales_order', :'c1', current_date, null, current_date + 5, null, :'wh', 'PO-C1-1', 'First order', :'q1',
  jsonb_build_array(
    jsonb_build_object('product_id', :'p1', 'quantity', 10, 'unit_price', 15, 'discount_amount', 10, 'tax_rate_id', :'vat', 'source_line_id', :'ql1'),
    jsonb_build_object('product_id', :'p3', 'quantity', 1, 'unit_price', 200, 'source_line_id', :'ql2'))) as so1 \gset
select public.t_assert((select total from trade_documents where id = :'so1') = 347, 'order total');
select public.t_assert((select status from trade_documents where id = :'q1') = 'converted', 'quotation converted');
select public.t_expect_error(format($q$select public.cancel_sales_document(%L, 'no longer needed')$q$, :'q1'), 'Cancel that order first');
select id as ol1 from trade_document_lines where document_id = :'so1' and line_no = 1 \gset
select id as ol2 from trade_document_lines where document_id = :'so1' and line_no = 2 \gset
select public.submit_sales_document(:'so1');
select public.t_assert((select status from trade_documents where id = :'so1') = 'pending', 'order pending');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000502', false);
select public.t_expect_error(format($q$select public.approve_sales_document(%L)$q$, :'so1'), 'permission');
select public.t_assert((select count(*) from trade_documents) = 0, 'employee sees no sales documents');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000504', false);
select public.approve_sales_document(:'so1');
select public.t_assert((select status from trade_documents where id = :'so1') = 'approved', 'order approved');

\echo '== 4. invoices from the order: partial invoicing, stock issue and cost of goods'
select public.t_expect_error(format($q$select public.save_sales_document(gen_random_uuid(), %L, 'sales_invoice', %L, current_date, null, null, null, null, null, null, %L,
  jsonb_build_array(jsonb_build_object('product_id', %L, 'quantity', 2, 'unit_price', 15, 'source_line_id', %L)))$q$,
  :'org', :'c1', :'so1', :'p1', :'ol1'), 'warehouse');
select public.save_sales_document(gen_random_uuid(), :'org', 'sales_invoice', :'c1', current_date, null, null, null, :'wh', 'PO-C1-1', null, :'so1',
  jsonb_build_array(
    jsonb_build_object('product_id', :'p1', 'quantity', 6, 'unit_price', 15, 'tax_rate_id', :'vat', 'source_line_id', :'ol1'),
    jsonb_build_object('product_id', :'p3', 'quantity', 1, 'unit_price', 200, 'source_line_id', :'ol2'))) as inv1 \gset
select public.t_assert((select total from trade_documents where id = :'inv1') = 294.5, 'invoice 1 total 294.5');
select public.t_assert((select due_date from trade_documents where id = :'inv1') = current_date + 30, 'due date from customer terms');
select public.t_expect_error(format($q$select public.save_sales_document(gen_random_uuid(), %L, 'sales_invoice', %L, current_date, null, null, null, %L, null, null, %L,
  jsonb_build_array(jsonb_build_object('product_id', %L, 'quantity', 5, 'unit_price', 15, 'source_line_id', %L)))$q$,
  :'org', :'c1', :'wh', :'so1', :'p1', :'ol1'), 'only 4 remain');
select public.t_expect_error(format($q$select public.cancel_sales_document(%L, 'oops')$q$, :'so1'), 'Cancel those first');
select public.post_sales_invoice(:'inv1');
select public.t_assert((select status from trade_documents where id = :'inv1') = 'posted', 'invoice 1 posted');
select public.t_assert((select status from trade_documents where id = :'so1') = 'partial', 'order partially invoiced');
select public.t_assert((select quantity from stock_balances where product_id = :'p1') = 94, 'widget stock 94');
select public.t_assert((select value from stock_balances where product_id = :'p1') = 940, 'widget value 940 at average cost');
select public.t_assert(public.t_bal(:'org', 'accounts_receivable') = 294.5, 'receivable 294.5');
select public.t_assert(public.t_bal(:'org', 'sales_revenue') = -290, 'revenue 290');
select public.t_assert(public.t_bal(:'org', 'output_tax') = -4.5, 'output tax 4.5');
select public.t_assert(public.t_bal(:'org', 'cogs') = 60, 'cost of goods 60');
select public.t_assert((select balance from document_balances where document_id = :'inv1') = 294.5, 'invoice balance');
select public.t_assert((select payment_status from document_balances where document_id = :'inv1') = 'unpaid', 'invoice unpaid');
select public.save_sales_document(gen_random_uuid(), :'org', 'sales_invoice', :'c1', current_date, null, null, null, :'wh', 'PO-C1-1', null, :'so1',
  jsonb_build_array(jsonb_build_object('product_id', :'p1', 'quantity', 4, 'unit_price', 15, 'tax_rate_id', :'vat', 'source_line_id', :'ol1'))) as inv2 \gset
select public.t_assert((select total from trade_documents where id = :'inv2') = 63, 'invoice 2 total 63');
select public.submit_sales_document(:'inv2');
select public.post_sales_invoice(:'inv2');
select public.t_assert((select status from trade_documents where id = :'so1') = 'invoiced', 'order fully invoiced');
select public.t_expect_error(format($q$select public.cancel_sales_document(%L, 'oops')$q$, :'so1'), 'Close it instead');
select public.t_assert((select sum(invoiced_qty) from public.sales_order_progress(:'so1')) = 11, 'progress shows 11 invoiced');
select public.t_assert(public.t_bal(:'org', 'accounts_receivable') = 357.5, 'receivable 357.5');
select public.t_assert(public.t_bal(:'org', 'cogs') = 100, 'cost of goods 100');
select public.t_assert((select count(*) from stock_movements where source_type = 'sales_invoice' and movement_type = 'sales_issue') = 2, 'two sales issues');

\echo '== 5. credit limit'
select public.save_sales_document(gen_random_uuid(), :'org', 'sales_invoice', :'c4', current_date, null, null, null, null, null, null, null,
  jsonb_build_array(jsonb_build_object('product_id', :'p4', 'quantity', 1, 'unit_price', 150))) as inv_lim \gset
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000502', false);
select public.t_expect_error(format($q$select public.post_sales_invoice(%L)$q$, :'inv_lim'), 'permission');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000504', false);
select public.t_expect_error(format($q$select public.post_sales_invoice(%L)$q$, :'inv_lim'), 'Credit limit exceeded');
select public.t_assert((select status from trade_documents where id = :'inv_lim') = 'draft', 'invoice still a draft after refusal');
select public.post_sales_invoice(:'inv_lim', true);
select public.t_assert((select credit_overridden from trade_documents where id = :'inv_lim'), 'override recorded');
select public.t_assert(public.t_bal(:'org', 'accounts_receivable') = 507.5, 'receivable 507.5');

\echo '== 6. opening balances as invoices and bills'
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000504', false);
select public.t_expect_error(format($q$select public.post_opening_balance(%L, 'receivable', %L, current_date - 70, null, 'OLD-INV-9', 500)$q$, :'org', :'c2'), 'permission');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000503', false);
select public.t_expect_error(format($q$select public.post_opening_balance(%L, 'receivable', %L, current_date - 70, null, null, 0)$q$, :'org', :'c2'), 'greater than zero');
select public.t_expect_error(format($q$select public.post_opening_balance(%L, 'receivable', %L, current_date - 70, null, null, 100)$q$, :'org', :'s1'), 'Choose a customer');
select public.t_bal(:'org', 'opening_balance_equity') as eq0 \gset
select public.post_opening_balance(:'org', 'receivable', :'c2', current_date - 70, null, 'OLD-INV-9', 500) as ob1 \gset
select public.t_assert((select number from trade_documents where id = :'ob1') = 'OINV-00001', 'opening invoice number');
select public.t_assert((select is_opening and status = 'posted' and due_date = current_date - 70 from trade_documents where id = :'ob1'), 'opening invoice posted and due on its own date');
select public.t_assert((select opening_receivable from parties where id = :'c2') = 0, 'profile balance moved into the books');
select public.t_assert(public.t_bal(:'org', 'accounts_receivable') = 1007.5, 'receivable 1007.5');
select public.t_assert(public.t_bal(:'org', 'opening_balance_equity') = :eq0 - 500, 'equity carries the opening receivable');
select public.post_opening_balance(:'org', 'receivable', :'c1', current_date - 10, current_date + 20, 'OLD-77', 300) as ob2 \gset
select public.post_opening_balance(:'org', 'payable', :'s1', current_date - 40, null, 'SUP-OLD-1', 800) as ob3 \gset
select public.t_assert((select number from trade_documents where id = :'ob3') = 'OBILL-00001', 'opening bill number');
select public.t_assert((select due_date from trade_documents where id = :'ob3') = current_date - 25, 'opening bill due from supplier terms');
select public.t_assert(public.t_bal(:'org', 'accounts_payable') = -800, 'payable 800');
select public.t_expect_error(format($q$select public.post_opening_balance(%L, 'payable', %L, current_date - 40, null, ' sup-old-1 ', 50)$q$, :'org', :'s1'), 'already exists');
select public.post_opening_balance(:'org', 'receivable', :'c2', current_date - 5, null, null, 100) as ob_x \gset
select public.t_assert(public.t_bal(:'org', 'accounts_receivable') = 1407.5, 'receivable 1407.5');
select public.t_expect_error(format($q$select public.cancel_sales_document(%L, 'entered twice')$q$, :'ob_x'), 'permission');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000501', false);
select public.cancel_sales_document(:'ob_x', 'entered twice');
select public.t_assert((select status from trade_documents where id = :'ob_x') = 'cancelled', 'opening invoice cancelled');
select public.t_assert(public.t_bal(:'org', 'accounts_receivable') = 1307.5, 'receivable back to 1307.5');

\echo '== 7. customer receipts and allocation'
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000503', false);
select public.record_payment(gen_random_uuid(), :'org', 'receipt', :'c2', current_date, :'fin_cash', null, 200, 'CASH-1', null,
  jsonb_build_array(jsonb_build_object('document_id', :'ob1', 'amount', 200))) as r1 \gset
select public.t_assert((select number from payments where id = :'r1') = 'RCT-00001', 'receipt number');
select public.t_assert((select balance from document_balances where document_id = :'ob1') = 300, 'opening invoice balance 300');
select public.t_assert((select payment_status from document_balances where document_id = :'ob1') = 'partial', 'opening invoice partial');
select public.t_assert(public.t_acct_bal(:'org', :'gl_cash') = 200, 'cash account up by 200');
select public.t_assert(public.t_bal(:'org', 'accounts_receivable') = 1107.5, 'receivable 1107.5');
select public.t_expect_error(format($q$select public.record_payment(gen_random_uuid(), %L, 'receipt', %L, current_date, %L, null, 400, null, null,
  jsonb_build_array(jsonb_build_object('document_id', %L, 'amount', 400)))$q$, :'org', :'c2', :'fin_cash', :'ob1'), 'still to pay');
select public.t_expect_error(format($q$select public.record_payment(gen_random_uuid(), %L, 'receipt', %L, current_date, %L, null, 100, null, null,
  jsonb_build_array(jsonb_build_object('document_id', %L, 'amount', 150)))$q$, :'org', :'c2', :'fin_cash', :'ob1'), 'more than the payment');
select public.t_expect_error(format($q$select public.record_payment(gen_random_uuid(), %L, 'receipt', %L, current_date, %L, null, 100, null, null,
  jsonb_build_array(jsonb_build_object('document_id', %L, 'amount', 50)))$q$, :'org', :'c1', :'fin_cash', :'ob1'), 'different customer');
select public.t_expect_error(format($q$select public.record_payment(gen_random_uuid(), %L, 'receipt', %L, current_date, %L, null, 100, null, null,
  jsonb_build_array(jsonb_build_object('document_id', %L, 'amount', 20), jsonb_build_object('document_id', %L, 'amount', 20)))$q$,
  :'org', :'c2', :'fin_cash', :'ob1', :'ob1'), 'only once');
select public.t_expect_error(format($q$select public.record_payment(gen_random_uuid(), %L, 'receipt', %L, current_date, %L, null, 100, null, null, null)$q$, :'org', :'s1', :'fin_cash'), 'Choose a customer');
select public.t_expect_error(format($q$select public.record_payment(%L, %L, 'receipt', %L, current_date, %L, null, 100, null, null, null)$q$, :'r1', :'org', :'c2', :'fin_cash'), 'already been recorded');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000502', false);
select public.t_expect_error(format($q$select public.record_payment(gen_random_uuid(), %L, 'receipt', %L, current_date, %L, null, 100, null, null, null)$q$, :'org', :'c2', :'fin_cash'), 'permission');

-- Sales Manager may record receipts. 1000 received: 457.5 applied, 542.5 stays as advance.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000504', false);
select public.record_payment(gen_random_uuid(), :'org', 'receipt', :'c1', current_date, :'fin_bank', null, 1000, 'TXN-88', 'Part payment',
  jsonb_build_array(jsonb_build_object('document_id', :'inv1', 'amount', 294.5),
                    jsonb_build_object('document_id', :'inv2', 'amount', 63),
                    jsonb_build_object('document_id', :'ob2', 'amount', 100))) as r2 \gset
select public.t_assert((select allocated from payment_balances where payment_id = :'r2') = 457.5, 'allocated 457.5');
select public.t_assert((select unallocated from payment_balances where payment_id = :'r2') = 542.5, 'advance 542.5');
select public.t_assert(public.t_bal(:'org', 'customer_advance') = -542.5, 'customer advance ledger 542.5');
select public.t_assert(public.t_bal(:'org', 'accounts_receivable') = 650, 'receivable 650');
select public.t_assert((select payment_status from document_balances where document_id = :'inv1') = 'paid', 'invoice 1 paid');
select public.t_assert(public.t_acct_bal(:'org', :'gl_bank') = 1000, 'bank up by 1000');

-- Apply part of the advance later.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000503', false);
select public.t_expect_error(format($q$select public.apply_advance(%L, %L, 50)$q$, :'r2', :'inv1'), 'still to pay');
select public.t_expect_error(format($q$select public.apply_advance(%L, %L, 50)$q$, :'r2', :'ob1'), 'different party');
select public.t_expect_error(format($q$select public.apply_advance(%L, %L, 9999)$q$, :'r2', :'ob2'), 'unapplied');
select public.apply_advance(:'r2', :'ob2', 200);
select public.t_assert((select unallocated from payment_balances where payment_id = :'r2') = 342.5, 'advance 342.5 after applying');
select public.t_assert(public.t_bal(:'org', 'customer_advance') = -342.5, 'customer advance ledger 342.5');
select public.t_assert(public.t_bal(:'org', 'accounts_receivable') = 450, 'receivable 450');
select public.t_assert((select payment_status from document_balances where document_id = :'ob2') = 'paid', 'opening invoice 2 paid');

-- Unapplying needs approval rights.
select id as alloc_inv2 from payment_allocations where payment_id = :'r2' and document_id = :'inv2' \gset
select public.t_expect_error(format($q$select public.unapply_allocation(%L, 'wrong invoice')$q$, :'alloc_inv2'), 'permission');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000501', false);
select public.t_expect_error(format($q$select public.unapply_allocation(%L, null)$q$, :'alloc_inv2'), 'Give a reason');
select public.unapply_allocation(:'alloc_inv2', 'wrong invoice');
select public.t_assert((select balance from document_balances where document_id = :'inv2') = 63, 'invoice 2 open again');
select public.t_assert((select unallocated from payment_balances where payment_id = :'r2') = 405.5, 'advance 405.5 after unapply');
select public.t_assert(public.t_bal(:'org', 'accounts_receivable') = 513, 'receivable 513');
select public.t_expect_error(format($q$select public.unapply_allocation(%L, 'again')$q$, :'alloc_inv2'), 'already been removed');

-- Cancelling a payment whose allocations were changed afterwards still balances.
select public.cancel_payment(:'r2', 'Bounced at the bank');
select public.t_assert((select status from payments where id = :'r2') = 'cancelled', 'receipt cancelled');
select public.t_assert((select balance from document_balances where document_id = :'inv1') = 294.5, 'invoice 1 open again');
select public.t_assert((select balance from document_balances where document_id = :'ob2') = 300, 'opening invoice 2 open again');
select public.t_assert(public.t_bal(:'org', 'customer_advance') = 0, 'no customer advance left');
select public.t_assert(public.t_bal(:'org', 'accounts_receivable') = (select sum(balance) from document_balances where doc_type = 'sales_invoice'), 'receivable equals open invoices');
select public.t_assert(public.t_acct_bal(:'org', :'gl_bank') = 0, 'bank back to zero');
select public.t_assert((select reversed_by is not null from vouchers where id = (select voucher_id from payments where id = :'r2')), 'receipt voucher marked reversed');
select public.t_expect_error(format($q$select public.cancel_payment(%L, 'again')$q$, :'r2'), 'already cancelled');

-- Simple cancellation mirrors the original entry.
select public.record_payment(gen_random_uuid(), :'org', 'receipt', :'c2', current_date, :'fin_cash', null, 50, null, null,
  jsonb_build_array(jsonb_build_object('document_id', :'ob1', 'amount', 50))) as r3 \gset
select public.t_assert((select balance from document_balances where document_id = :'ob1') = 250, 'opening invoice 250 after 50');
select public.cancel_payment(:'r3', 'Entered by mistake');
select public.t_assert((select balance from document_balances where document_id = :'ob1') = 300, 'opening invoice back to 300');
select public.t_assert(public.t_bal(:'org', 'accounts_receivable') = (select sum(balance) from document_balances where doc_type = 'sales_invoice'), 'receivable equals open invoices after simple cancel');

-- A paid invoice cannot be cancelled.
select public.record_payment(gen_random_uuid(), :'org', 'receipt', :'c1', current_date, :'fin_bank', null, 294.5, null, null,
  jsonb_build_array(jsonb_build_object('document_id', :'inv1', 'amount', 294.5))) as r4 \gset
select public.t_expect_error(format($q$select public.cancel_sales_document(%L, 'wrong customer')$q$, :'inv1'), 'payments applied');

\echo '== 8. supplier bills and payments'
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000505', false);
select public.save_purchase_document(gen_random_uuid(), :'org', 'supplier_bill', :'s1', current_date, null, null, null, null, null, 'SUP-INV-5', 'Office rent',
  null, jsonb_build_array(jsonb_build_object('description', 'Office rent', 'quantity', 1, 'unit_price', 1000, 'account_id', :'acc_util'))) as b1 \gset
select public.post_supplier_bill(:'b1');
select public.t_assert(public.t_bal(:'org', 'accounts_payable') = -1800, 'payable 1800');
select public.t_expect_error(format($q$select public.record_payment(gen_random_uuid(), %L, 'payment', %L, current_date, %L, null, 100, null, null, null)$q$, :'org', :'s1', :'fin_cash'), 'permission');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000503', false);
select public.record_payment(gen_random_uuid(), :'org', 'payment', :'s1', current_date, :'fin_cash', null, 500, 'CHQ-1', null,
  jsonb_build_array(jsonb_build_object('document_id', :'ob3', 'amount', 500))) as sp1 \gset
select public.t_assert((select number from payments where id = :'sp1') = 'SPY-00001', 'supplier payment number');
select public.t_assert((select balance from document_balances where document_id = :'ob3') = 300, 'opening bill balance 300');
select public.t_assert(public.t_bal(:'org', 'accounts_payable') = -1300, 'payable 1300');
select public.t_assert(public.t_acct_bal(:'org', :'gl_cash') = 200 - 500, 'cash after paying the supplier');
select public.t_expect_error(format($q$select public.record_payment(gen_random_uuid(), %L, 'payment', %L, current_date, %L, null, 100, null, null,
  jsonb_build_array(jsonb_build_object('document_id', %L, 'amount', 50)))$q$, :'org', :'s1', :'fin_cash', :'ob1'), 'Choose a posted bill');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000501', false);
select public.record_payment(gen_random_uuid(), :'org', 'payment', :'s1', current_date, :'fin_bank', null, 1500, null, null,
  jsonb_build_array(jsonb_build_object('document_id', :'ob3', 'amount', 300), jsonb_build_object('document_id', :'b1', 'amount', 1000))) as sp2 \gset
select public.t_assert(public.t_bal(:'org', 'accounts_payable') = 0, 'payable cleared');
select public.t_assert(public.t_bal(:'org', 'supplier_advance') = 200, 'advance to supplier 200');
select public.t_expect_error(format($q$select public.cancel_document(%L, 'duplicate bill')$q$, :'b1'), 'payments applied');
select public.cancel_payment(:'sp2', 'Wrong bank');
select public.t_assert(public.t_bal(:'org', 'accounts_payable') = -1300, 'payable back to 1300');
select public.t_assert(public.t_bal(:'org', 'supplier_advance') = 0, 'no supplier advance left');
select public.record_payment(gen_random_uuid(), :'org', 'payment', :'s1', current_date, :'fin_cash', null, 400, null, 'Advance for next order', null) as sp3 \gset
select public.t_assert(public.t_bal(:'org', 'supplier_advance') = 400, 'pure advance to supplier 400');
select public.apply_advance(:'sp3', :'ob3', 300);
select public.t_assert((select unallocated from payment_balances where payment_id = :'sp3') = 100, 'supplier advance 100 left');
select public.t_assert(public.t_bal(:'org', 'accounts_payable') = -1000, 'payable 1000');
select public.t_assert(public.t_bal(:'org', 'supplier_advance') = 100, 'supplier advance ledger 100');

\echo '== 9. aging buckets'
select public.post_opening_balance(:'org', 'receivable', :'c5', current_date - 35, current_date + 5, null, 10) is not null as ok1 \gset
select public.post_opening_balance(:'org', 'receivable', :'c5', current_date - 45, current_date - 15, null, 20) is not null as ok2 \gset
select public.post_opening_balance(:'org', 'receivable', :'c5', current_date - 75, current_date - 45, null, 30) is not null as ok3 \gset
select public.post_opening_balance(:'org', 'receivable', :'c5', current_date - 105, current_date - 75, null, 40) is not null as ok4 \gset
select public.post_opening_balance(:'org', 'receivable', :'c5', current_date - 150, current_date - 120, null, 50) is not null as ok5 \gset
select public.t_assert((select current_amt = 10 and d1_30 = 20 and d31_60 = 30 and d61_90 = 40 and over_90 = 50
                          and total_due = 150 and overdue_total = 140 and open_count = 5 and oldest_days = 120
                          from public.party_aging(:'org', 'receivable', current_date, :'c5')), 'aging buckets today');
select public.t_assert((select current_amt = 40 and d1_30 = 50 and total_due = 90 from public.party_aging(:'org', 'receivable', current_date - 100, :'c5')), 'aging as of 100 days ago');
select public.t_assert((select count(*) from public.aging_documents(:'org', 'receivable', current_date, :'c5')) = 5, 'five open documents');
select public.t_assert((select party_name from public.aging_documents(:'org', 'payable', current_date, null) limit 1) = 'Alpha Supplies', 'payable aging lists suppliers');
select public.t_assert((select sum(balance) from public.aging_documents(:'org', 'payable', current_date, null)) = 1000, 'payable aging total 1000');
select public.t_assert((select advance from public.party_aging(:'org', 'payable', current_date, :'s1')) = 100, 'payable aging shows the advance');

\echo '== 10. control accounts agree with the open documents'
select public.t_assert((select ledger_open = documents_open and ledger_advance = advances_open from public.aging_control_check(:'org') where side = 'receivable'), 'receivable control account agrees');
select public.t_assert((select ledger_open = documents_open and ledger_advance = advances_open from public.aging_control_check(:'org') where side = 'payable'), 'payable control account agrees');

\echo '== 11. statements and profile figures'
select public.t_assert((select count(*) from public.party_statement(:'org', :'c2', 'customer')) = 2, 'statement has the invoice and the receipt');
select public.t_assert((select balance from public.party_statement(:'org', :'c2', 'customer') order by entry_date desc, number desc limit 1) = 300, 'statement ends at 300');
select public.t_assert((select row_type from public.party_statement(:'org', :'c2', 'customer', current_date - 5) limit 1) = 'opening', 'statement starts with the opening row');
select public.t_assert((select balance from public.party_statement(:'org', :'c2', 'customer', current_date - 5) limit 1) = 500, 'opening balance before the period is 500');
select public.t_assert((select count(*) from public.party_statement(:'org', :'s1', 'supplier')) = 4 and (select balance from public.party_statement(:'org', :'s1', 'supplier') order by entry_date desc, balance desc limit 1) is not null, 'supplier statement lists two bills and two payments');
select public.t_assert((select receivable_open = 363 and receivable_advance = 0 and credit_limit = 5000 and available_credit = 4637
                          from public.party_summary(:'org', :'c1')), 'customer summary');
select public.t_assert((select payable_open = 1000 and payable_advance = 100 from public.party_summary(:'org', :'s1')), 'supplier summary');

\echo '== 12. cancelling an invoice returns stock at the cost it left at'
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000504', false);
select public.save_sales_document(gen_random_uuid(), :'org', 'sales_invoice', :'c2', current_date, null, null, null, :'wh', null, null, null,
  jsonb_build_array(jsonb_build_object('product_id', :'p2', 'quantity', 5, 'unit_price', 60))) as inv3 \gset
select public.post_sales_invoice(:'inv3');
select public.t_assert((select quantity from stock_balances where product_id = :'p2') = 45, 'gadget stock 45');
select public.cancel_sales_document(:'inv3', 'Customer changed their mind');
select public.t_assert((select quantity from stock_balances where product_id = :'p2') = 50 and (select value from stock_balances where product_id = :'p2') = 2000, 'gadget stock restored');
select public.t_assert((select count(*) from stock_movements where source_id = :'inv3' and movement_type = 'reversal') = 1, 'reversal movement recorded');
select public.t_assert((select status from trade_documents where id = :'inv3') = 'cancelled', 'invoice cancelled');
select public.t_expect_error(format($q$select public.cancel_sales_document(%L, 'again')$q$, :'inv3'), 'already cancelled');

-- Emptying the stock and cancelling must give back exactly the value that left.
select public.t_assert((select quantity = 3000 and value = 1000.10 from stock_balances where product_id = :'p5'), 'bulk stock 3000 worth 1000.10');
select public.save_sales_document(gen_random_uuid(), :'org', 'sales_invoice', :'c2', current_date, null, null, null, :'wh', null, null, null,
  jsonb_build_array(jsonb_build_object('product_id', :'p5', 'quantity', 3000, 'unit_price', 1))) as inv4 \gset
select public.post_sales_invoice(:'inv4');
select public.t_assert((select quantity = 0 and value = 0 from stock_balances where product_id = :'p5'), 'bulk stock emptied');
select public.t_assert(public.t_bal(:'org', 'cogs') = 100 + 1000.10, 'cost of goods includes the bulk sale at its true cost');
select public.cancel_sales_document(:'inv4', 'Wrong quantity');
select public.t_assert((select quantity = 3000 and value = 1000.10 from stock_balances where product_id = :'p5'), 'bulk stock value restored to the cent');
select public.t_assert(public.t_bal(:'org', 'cogs') = 100, 'cost of goods back to 100');
select public.t_assert(public.t_bal(:'org', 'inventory') = (select sum(value) from stock_balances where org_id = :'org'), 'inventory ledger equals stock value');

\echo '== 13. order workflow: reject, close, discard'
select public.save_sales_document(gen_random_uuid(), :'org', 'sales_order', :'c2', current_date, null, null, null, :'wh', null, null, null,
  jsonb_build_array(jsonb_build_object('product_id', :'p4', 'quantity', 1, 'unit_price', 50))) as so2 \gset
select public.submit_sales_document(:'so2');
select public.t_expect_error(format($q$select public.reject_sales_document(%L, '')$q$, :'so2'), 'reason');
select public.reject_sales_document(:'so2', 'Price is wrong');
select public.t_assert((select status = 'rejected' and rejection_reason = 'Price is wrong' from trade_documents where id = :'so2'), 'order rejected with reason');
select public.save_sales_document(:'so2', :'org', 'sales_order', :'c2', current_date, null, null, null, :'wh', null, null, null,
  jsonb_build_array(jsonb_build_object('product_id', :'p4', 'quantity', 1, 'unit_price', 55))) is not null as resaved \gset
select public.t_assert((select status = 'draft' and total = 55 from trade_documents where id = :'so2'), 'rejected order edited back to draft');
select public.submit_sales_document(:'so2');
select public.approve_sales_document(:'so2');
select public.close_sales_order(:'so2', 'Customer cancelled the project');
select public.t_assert((select status from trade_documents where id = :'so2') = 'closed', 'order closed');
select public.t_expect_error(format($q$select public.save_sales_document(gen_random_uuid(), %L, 'sales_invoice', %L, current_date, null, null, null, %L, null, null, %L,
  jsonb_build_array(jsonb_build_object('product_id', %L, 'quantity', 1, 'unit_price', 55)))$q$, :'org', :'c2', :'wh', :'so2', :'p4'), 'approved sales order');
select public.save_sales_document(gen_random_uuid(), :'org', 'sales_quotation', :'c2', current_date, null, null, null, null, null, null, null,
  jsonb_build_array(jsonb_build_object('product_id', :'p4', 'quantity', 1, 'unit_price', 55))) as q2 \gset
select public.discard_sales_document(:'q2');
select public.t_assert((select count(*) from trade_documents where id = :'q2') = 0, 'draft quotation discarded');

\echo '== 14. posted records are protected'
reset role;
select public.t_expect_error('delete from payments', 'cannot be deleted');
select public.t_expect_error('update payments set amount = 1', 'cannot be changed');
select public.t_expect_error('delete from payment_allocations', 'cannot be deleted');
select public.t_expect_error('update payment_allocations set amount = 1', 'cannot be changed');
select public.t_expect_error(format($q$update trade_documents set total = 1 where id = %L$q$, :'inv1'), 'cannot be changed');

\echo '== 15. visibility follows permissions'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000502', false);
select public.t_assert((select count(*) from payments) = 0, 'employee sees no payments');
select public.t_assert((select count(*) from document_balances) = 0, 'employee sees no balances');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000505', false);
select public.t_assert((select count(*) from payments where kind = 'receipt') = 0, 'purchase manager sees no receipts');
select public.t_assert((select count(*) from payments where kind = 'payment') > 0, 'purchase manager sees supplier payments');
select public.t_assert((select count(*) from document_balances where doc_type = 'sales_invoice') = 0, 'purchase manager sees no invoice balances');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000506', false);
select public.t_assert((select count(*) from payments where kind = 'receipt') > 0 and (select count(*) from payments where kind = 'payment') > 0, 'auditor sees both kinds');
select public.t_expect_error(format($q$select public.cancel_payment(%L, 'no')$q$, :'r4'), 'permission');

reset role;
\echo 'ALL TESTS PASSED'
