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

create or replace function public.t_rows(p_sql text) returns bigint language plpgsql as $$
declare v bigint; begin execute p_sql; get diagnostics v = row_count; return v; end $$;

create or replace function public.t_num(p_sql text) returns numeric language plpgsql as $$
declare v numeric; begin execute p_sql into v; return v; end $$;

-- Users ---------------------------------------------------------------
insert into auth.users (id, email) values
 ('00000000-0000-0000-0000-000000000001', 'owner@t.com'),
 ('00000000-0000-0000-0000-000000000002', 'employee@t.com'),
 ('00000000-0000-0000-0000-000000000003', 'store@t.com'),
 ('00000000-0000-0000-0000-000000000004', 'auditor@t.com'),
 ('00000000-0000-0000-0000-000000000005', 'buyer@t.com'),
 ('00000000-0000-0000-0000-000000000006', 'pm@t.com');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);
set role authenticated;
select public.create_organization('Test Co') as org \gset
reset role;

select set_config('app.bootstrap', 'on', false);
insert into organization_members (org_id, user_id, role_id)
select :'org', u.id, r.id from (values
  ('00000000-0000-0000-0000-000000000002'::uuid, 'Employee / Staff'),
  ('00000000-0000-0000-0000-000000000003'::uuid, 'Inventory / Store Manager'),
  ('00000000-0000-0000-0000-000000000004'::uuid, 'Auditor / Viewer'),
  ('00000000-0000-0000-0000-000000000005'::uuid, 'Purchase Manager'),
  ('00000000-0000-0000-0000-000000000006'::uuid, 'Project Manager')) as u(id, role)
join roles r on r.org_id = :'org' and r.name = u.role;
select set_config('app.bootstrap', 'off', false);

-- Master data as owner (through RLS) ----------------------------------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);
set role authenticated;

insert into parties (org_id, name, is_supplier, payment_terms_days) values (:'org', 'Alpha Supplies', true, 30) returning id as s1 \gset
insert into parties (org_id, name, is_supplier) values (:'org', 'Beta Traders', true) returning id as s2 \gset
insert into products (org_id, name, item_type, track_inventory) values (:'org', 'Widget', 'product', true) returning id as p1 \gset
insert into products (org_id, name, item_type, track_inventory) values (:'org', 'Gadget', 'product', true) returning id as p2 \gset
insert into products (org_id, name, item_type) values (:'org', 'Delivery', 'service') returning id as p3 \gset
insert into products (org_id, name, item_type, track_inventory) values (:'org', 'Stationery', 'product', false) returning id as p4 \gset
insert into tax_rates (org_id, name, rate, applies_to) values (:'org', 'Test VAT 5', 5, 'both') returning id as vat \gset
select id as wh from warehouses where org_id = :'org' and is_default \gset
select id as acc_util from accounts where org_id = :'org' and code = '5320' \gset
select id as acc_inv from accounts where org_id = :'org' and system_key = 'inventory' \gset
select id as acc_grni from accounts where org_id = :'org' and system_key = 'grni' \gset
select id as acc_ap from accounts where org_id = :'org' and system_key = 'accounts_payable' \gset
select id as acc_ppv from accounts where org_id = :'org' and system_key = 'purchase_variance' \gset
select id as acc_tax from accounts where org_id = :'org' and system_key = 'input_tax' \gset
select id as acc_adj from accounts where org_id = :'org' and system_key = 'inventory_adjustment' \gset

\echo '== 1. system accounts seeded'
select public.t_assert(count(*) = 3, 'three trade system accounts') from accounts where org_id = :'org' and system_key in ('grni', 'purchase_variance', 'inventory_adjustment');

\echo '== 2. requisition: employee creates, cannot approve, owner approves'
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', false);
select public.save_purchase_document(gen_random_uuid(), :'org', 'purchase_requisition', null, current_date, null, current_date + 7,
  null, null, null, null, 'Need stock for the month', null,
  jsonb_build_array(jsonb_build_object('product_id', :'p1', 'quantity', 100, 'unit_price', 10),
                    jsonb_build_object('product_id', :'p2', 'quantity', 20, 'unit_price', 50),
                    jsonb_build_object('product_id', :'p3', 'quantity', 1, 'unit_price', 200))) as req \gset
select public.submit_document(:'req');
select public.t_expect_error(format($q$select public.approve_document(%L)$q$, :'req'), 'permission');
select public.t_assert((select count(*) from trade_documents) = 1, 'employee sees own requisition');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000006', false);
select public.t_assert((select count(*) from trade_documents) = 0, 'project manager does not see another user''s requisition');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', false);
select public.t_assert((select count(*) from trade_documents) = 1, 'store manager has purchase view and sees requisitions');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);
select public.approve_document(:'req');
select public.t_assert((select status from trade_documents where id = :'req') = 'approved', 'requisition approved');

\echo '== 3. purchase order from requisition'
select public.save_purchase_document(gen_random_uuid(), :'org', 'purchase_order', :'s1', current_date, null, current_date + 10,
  null, :'wh', null, 'Quote 77', 'Monthly order', :'req',
  jsonb_build_array(
    jsonb_build_object('product_id', :'p1', 'quantity', 100, 'unit_price', 10, 'discount_amount', 50, 'tax_rate_id', :'vat'),
    jsonb_build_object('product_id', :'p2', 'quantity', 20, 'unit_price', 50),
    jsonb_build_object('product_id', :'p3', 'quantity', 1, 'unit_price', 200))) as po \gset
select public.t_assert((select status from trade_documents where id = :'req') = 'ordered', 'requisition marked ordered');
select public.t_assert((select subtotal from trade_documents where id = :'po') = 2200, 'po subtotal');
select public.t_assert((select discount_total from trade_documents where id = :'po') = 50, 'po discount');
select public.t_assert((select tax_total from trade_documents where id = :'po') = 47.5, 'po tax');
select public.t_assert((select total from trade_documents where id = :'po') = 2197.5, 'po total');
select public.submit_document(:'po');
select public.approve_document(:'po');
select public.t_assert((select status from trade_documents where id = :'po') = 'approved', 'po approved');
select id as pol1 from trade_document_lines where document_id = :'po' and line_no = 1 \gset
select id as pol2 from trade_document_lines where document_id = :'po' and line_no = 2 \gset
select id as pol3 from trade_document_lines where document_id = :'po' and line_no = 3 \gset
select public.t_expect_error(format($q$select public.cancel_document(%L, 'x')$q$, :'req'), 'purchase order has been raised');

\echo '== 4. goods receipt 1 (store manager), partial'
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', false);
select public.t_expect_error(format($q$select public.save_purchase_document(gen_random_uuid(), %L, 'goods_receipt', %L, current_date, null, null, null, %L, null, null, null, %L,
  jsonb_build_array(jsonb_build_object('product_id', %L, 'quantity', 101, 'unit_price', 9.5, 'source_line_id', %L)))$q$, :'org', :'s1', :'wh', :'po', :'p1', :'pol1'),
  'Line 1: only 100 remain') ;
select public.save_purchase_document(gen_random_uuid(), :'org', 'goods_receipt', :'s1', current_date, null, null, null, :'wh', null, 'DN-1', null, :'po',
  jsonb_build_array(jsonb_build_object('product_id', :'p1', 'quantity', 60, 'unit_price', 9.5, 'source_line_id', :'pol1'),
                    jsonb_build_object('product_id', :'p2', 'quantity', 20, 'unit_price', 50, 'source_line_id', :'pol2'))) as grn1 \gset
select public.post_goods_receipt(:'grn1');
reset role;
select public.t_assert((select quantity from stock_balances where product_id = :'p1' and warehouse_id = :'wh') = 60, 'p1 qty 60');
select public.t_assert((select value from stock_balances where product_id = :'p1' and warehouse_id = :'wh') = 570, 'p1 value 570');
select public.t_assert((select value from stock_balances where product_id = :'p2') = 1000, 'p2 value 1000');
select public.t_assert((select status from trade_documents where id = :'po') = 'partial', 'po partial');
select public.t_assert((select total_amount from vouchers where id = (select voucher_id from trade_documents where id = :'grn1')) = 1570, 'grn voucher 1570');
set role authenticated;

\echo '== 5. goods receipt 2 completes the order'
select public.save_purchase_document(gen_random_uuid(), :'org', 'goods_receipt', :'s1', current_date, null, null, null, :'wh', null, 'DN-2', null, :'po',
  jsonb_build_array(jsonb_build_object('product_id', :'p1', 'quantity', 40, 'unit_price', 9.5, 'source_line_id', :'pol1'))) as grn2 \gset
select public.post_goods_receipt(:'grn2');
select public.t_assert((select status from trade_documents where id = :'po') = 'received', 'po received');

\echo '== 6. direct receipt from other supplier without a PO updates average cost'
select public.save_purchase_document(gen_random_uuid(), :'org', 'goods_receipt', :'s2', current_date, null, null, null, :'wh', null, null, null, null,
  jsonb_build_array(jsonb_build_object('product_id', :'p1', 'quantity', 10, 'unit_price', 12))) as grn3 \gset
select public.post_goods_receipt(:'grn3');
reset role;
select public.t_assert((select quantity from stock_balances where product_id = :'p1') = 110, 'p1 qty 110');
select public.t_assert((select value from stock_balances where product_id = :'p1') = 1070, 'p1 value 1070');
select public.t_assert((select avg_cost from stock_balances where product_id = :'p1') = 9.7273, 'p1 avg 9.7273');
set role authenticated;

\echo '== 7. only stock items can be received'
select public.t_expect_error(format($q$select public.save_purchase_document(gen_random_uuid(), %L, 'goods_receipt', %L, current_date, null, null, null, %L, null, null, null, null,
  jsonb_build_array(jsonb_build_object('product_id', %L, 'quantity', 1, 'unit_price', 5)))$q$, :'org', :'s1', :'wh', :'p3'), 'only stock items');
select public.t_expect_error(format($q$select public.save_purchase_document(gen_random_uuid(), %L, 'goods_receipt', %L, current_date, null, null, null, %L, null, null, null, null,
  jsonb_build_array(jsonb_build_object('product_id', %L, 'quantity', 1, 'unit_price', 5)))$q$, :'org', :'s1', :'wh', :'p4'), 'only stock items');

\echo '== 8. supplier bill with matching, price variance and a service line'
select receipt_line_id as g1l1 from unbilled_receipt_lines(:'org', :'s1') where product_id = :'p1' order by receipt_number limit 1 \gset
select public.t_assert((select sum(remaining_qty) from unbilled_receipt_lines(:'org', :'s1') where product_id = :'p1') = 100, 'unbilled p1 100 for s1');
select public.t_assert((select count(*) from unbilled_receipt_lines(:'org', :'s2')) = 1, 'unbilled for s2 is its direct receipt');
select id as grn1l1 from trade_document_lines where document_id = :'grn1' and line_no = 1 \gset
select id as grn1l2 from trade_document_lines where document_id = :'grn1' and line_no = 2 \gset
select id as grn2l1 from trade_document_lines where document_id = :'grn2' and line_no = 1 \gset

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000005', false);
select public.t_expect_error(format($q$select public.save_purchase_document(gen_random_uuid(), %L, 'supplier_bill', %L, current_date, null, null, null, null, null, 'INV-9', null, null,
  jsonb_build_array(jsonb_build_object('product_id', %L, 'quantity', 5, 'unit_price', 10)))$q$, :'org', :'s1', :'p1'), 'billed from a goods receipt');
select public.t_expect_error(format($q$select public.save_purchase_document(gen_random_uuid(), %L, 'supplier_bill', %L, current_date, null, null, null, null, null, 'INV-9', null, null,
  jsonb_build_array(jsonb_build_object('product_id', %L, 'quantity', 61, 'unit_price', 10, 'source_line_id', %L)))$q$, :'org', :'s1', :'p1', :'grn1l1'), 'only 60 remain');
select public.save_purchase_document(gen_random_uuid(), :'org', 'supplier_bill', :'s1', current_date, null, null, null, null, null, 'SUP-INV-1', 'March bill', null,
  jsonb_build_array(
    jsonb_build_object('product_id', :'p1', 'quantity', 60, 'unit_price', 10, 'discount_amount', 30, 'tax_rate_id', :'vat', 'source_line_id', :'grn1l1'),
    jsonb_build_object('product_id', :'p1', 'quantity', 40, 'unit_price', 10, 'discount_amount', 20, 'tax_rate_id', :'vat', 'source_line_id', :'grn2l1'),
    jsonb_build_object('product_id', :'p2', 'quantity', 20, 'unit_price', 55, 'source_line_id', :'grn1l2'),
    jsonb_build_object('product_id', :'p3', 'quantity', 1, 'unit_price', 200, 'account_id', :'acc_util', 'source_line_id', :'pol3'))) as bill \gset
select public.t_assert((select total from trade_documents where id = :'bill') = 2297.5, 'bill total 2297.5');
select public.t_assert((select due_date from trade_documents where id = :'bill') = current_date + 30, 'due date from payment terms');
select public.t_expect_error(format($q$select public.save_purchase_document(gen_random_uuid(), %L, 'supplier_bill', %L, current_date, null, null, null, null, null, ' sup-inv-1 ', null, null,
  jsonb_build_array(jsonb_build_object('product_id', %L, 'quantity', 1, 'unit_price', 10, 'source_line_id', %L)))$q$, :'org', :'s1', :'p2', :'grn1l2'), 'already exists');
select public.submit_document(:'bill');
select public.post_supplier_bill(:'bill');
reset role;
select public.t_assert((select status from trade_documents where id = :'bill') = 'posted', 'bill posted');
select public.t_assert((select coalesce(sum(debit), 0) from voucher_lines where voucher_id = (select voucher_id from trade_documents where id = :'bill') and account_id = :'acc_grni') = 1950, 'grni debit 1950');
select public.t_assert((select coalesce(sum(debit), 0) from voucher_lines where voucher_id = (select voucher_id from trade_documents where id = :'bill') and account_id = :'acc_ppv') = 100, 'ppv debit 100');
select public.t_assert((select coalesce(sum(debit), 0) from voucher_lines where voucher_id = (select voucher_id from trade_documents where id = :'bill') and account_id = :'acc_util') = 200, 'utilities debit 200');
select public.t_assert((select coalesce(sum(debit), 0) from voucher_lines where voucher_id = (select voucher_id from trade_documents where id = :'bill') and account_id = :'acc_tax') = 47.5, 'input tax 47.5');
select public.t_assert((select coalesce(sum(credit), 0) from voucher_lines where voucher_id = (select voucher_id from trade_documents where id = :'bill') and account_id = :'acc_ap') = 2297.5, 'ap credit 2297.5');
select public.t_assert((select count(*) from voucher_lines where voucher_id = (select voucher_id from trade_documents where id = :'bill') and account_id = :'acc_ap' and party_id = :'s1') = 1, 'ap line carries supplier');
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);
select public.t_assert((select count(*) from unbilled_receipt_lines(:'org', :'s1')) = 0, 'everything billed for s1');
select public.t_assert((select count(*) from unbilled_order_lines(:'org', :'s1')) = 0, 'no service lines left to bill on the order');
select public.t_assert((select billed_qty from purchase_order_progress(:'po') where line_id = :'pol1') = 100, 'po progress: p1 billed 100');
select public.t_assert((select received_qty from purchase_order_progress(:'po') where line_id = :'pol1') = 100, 'po progress: p1 received 100');
select public.t_assert((select billed_qty from purchase_order_progress(:'po') where line_id = :'pol3') = 1, 'po progress: service billed 1');

\echo '== 9. cannot cancel a billed receipt; cancel bill then receipt'
select public.t_expect_error(format($q$select public.cancel_document(%L, 'wrong')$q$, :'grn1'), 'has been billed');
select public.cancel_document(:'bill', 'Supplier sent a corrected invoice');
select public.t_assert((select status from trade_documents where id = :'bill') = 'cancelled', 'bill cancelled');
select public.t_assert((select count(*) from unbilled_receipt_lines(:'org', :'s1')) = 3, 'receipt lines unbilled again');
select public.t_assert((select remaining_qty from unbilled_order_lines(:'org', :'s1') limit 1) = 1, 'service line on the order can be billed again');
select public.cancel_document(:'grn1', 'Goods were returned');
select public.t_assert((select status from trade_documents where id = :'grn1') = 'cancelled', 'grn1 cancelled');
select public.t_assert((select status from trade_documents where id = :'po') = 'partial', 'po back to partial after receipt cancelled');
reset role;
select public.t_assert((select quantity from stock_balances where product_id = :'p1') = 50, 'p1 qty 50 after reversal');
select public.t_assert((select value from stock_balances where product_id = :'p1') = 500, 'p1 value 500 after reversal');
select public.t_assert((select quantity from stock_balances where product_id = :'p2') = 0, 'p2 qty 0');
select public.t_assert((select value from stock_balances where product_id = :'p2') = 0, 'p2 value 0');
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);

\echo '== 10. immutability'
-- App users have no write policies, so these change nothing.
select public.t_assert(public.t_rows($q$update stock_movements set quantity = 1$q$) = 0, 'app users cannot update movements');
select public.t_assert(public.t_rows($q$delete from stock_movements$q$) = 0, 'app users cannot delete movements');
select public.t_assert(public.t_rows(format($q$update trade_documents set notes = 'x' where id = %L$q$, :'grn2')) = 0, 'app users cannot update documents directly');
-- Even a privileged connection is stopped by the triggers.
reset role;
select public.t_expect_error($q$update stock_movements set quantity = 1$q$, 'cannot be changed');
select public.t_expect_error($q$delete from stock_movements$q$, 'cannot be changed');
select public.t_expect_error(format($q$update trade_documents set notes = 'x' where id = %L$q$, :'grn2'), 'cannot be changed');
select public.t_expect_error(format($q$delete from trade_documents where id = %L$q$, :'grn2'), 'delete');
select public.t_expect_error(format($q$update trade_document_lines set quantity = 1 where document_id = %L$q$, :'grn2'), 'submitted');
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);

\echo '== 11. stock adjustments'
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', false);
select public.t_expect_error(format($q$select public.save_stock_adjustment(gen_random_uuid(), %L, current_date, %L, 'damaged', null,
  jsonb_build_array(jsonb_build_object('product_id', %L, 'quantity_change', 2)))$q$, :'org', :'wh', :'p1'), 'only reduce');
select public.t_expect_error(format($q$select public.save_stock_adjustment(gen_random_uuid(), %L, current_date, %L, 'count_correction', null,
  jsonb_build_array(jsonb_build_object('product_id', %L, 'quantity_change', 2, 'unit_cost', 5)))$q$, :'org', :'wh', :'p4'), 'does not track stock');
select public.t_expect_error(format($q$select public.save_stock_adjustment(gen_random_uuid(), %L, current_date, %L, 'count_correction', null,
  jsonb_build_array(jsonb_build_object('product_id', %L, 'quantity_change', 2)))$q$, :'org', :'wh', :'p1'), 'unit cost');
select public.save_stock_adjustment(gen_random_uuid(), :'org', current_date, :'wh', 'count_correction', 'Recount',
  jsonb_build_array(jsonb_build_object('product_id', :'p1', 'quantity_change', 10, 'unit_cost', 8),
                    jsonb_build_object('product_id', :'p2', 'quantity_change', 5, 'unit_cost', 40))) as adj1 \gset
select public.submit_stock_adjustment(:'adj1');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);
select public.approve_stock_adjustment(:'adj1');
select public.post_stock_adjustment(:'adj1');
reset role;
select public.t_assert((select quantity from stock_balances where product_id = :'p1') = 60, 'p1 qty 60 after adjustment');
select public.t_assert((select value from stock_balances where product_id = :'p1') = 580, 'p1 value 580 after adjustment');
select public.t_assert((select quantity from stock_balances where product_id = :'p2') = 5, 'p2 qty 5');
select public.t_assert((select coalesce(sum(credit), 0) from voucher_lines where account_id = :'acc_adj' and voucher_id = (select voucher_id from stock_adjustments where id = :'adj1')) = 280, 'adjustment gain credited 280');
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);
select public.save_stock_adjustment(gen_random_uuid(), :'org', current_date, :'wh', 'damaged', 'Water damage',
  jsonb_build_array(jsonb_build_object('product_id', :'p1', 'quantity_change', -5))) as adj2 \gset
select public.post_stock_adjustment(:'adj2');
reset role;
select public.t_assert((select quantity from stock_balances where product_id = :'p1') = 55, 'p1 qty 55 after damage');
select public.t_assert((select value from stock_balances where product_id = :'p1') = 531.67, 'p1 value 531.67 after damage (avg 9.6667 * 5 = 48.33)') ;
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);
select public.save_stock_adjustment(gen_random_uuid(), :'org', current_date, :'wh', 'lost', null,
  jsonb_build_array(jsonb_build_object('product_id', :'p2', 'quantity_change', -50))) as adj3 \gset
select public.t_expect_error(format($q$select public.post_stock_adjustment(%L)$q$, :'adj3'), 'Not enough stock');
select public.discard_stock_adjustment(:'adj3');
select public.t_assert((select count(*) from stock_adjustments where id = :'adj3') = 0, 'adjustment draft discarded');

\echo '== 12. invariants: balances = movements, and inventory ledger = stock value'
reset role;
select public.t_assert(not exists (
  select 1 from stock_balances b
  left join (select product_id, warehouse_id, sum(quantity) q, sum(value) v from stock_movements group by 1, 2) m
    on m.product_id = b.product_id and m.warehouse_id = b.warehouse_id
  where b.quantity <> coalesce(m.q, 0) or b.value <> coalesce(m.v, 0)), 'balances equal movement sums');
select public.t_assert(
  (select coalesce(sum(debit - credit), 0) from voucher_lines where account_id = :'acc_inv')
  = (select coalesce(sum(value), 0) from stock_balances), 'inventory GL equals stock valuation');
select public.t_assert((select coalesce(sum(debit), 0) from voucher_lines) = (select coalesce(sum(credit), 0) from voucher_lines), 'books balance');
select public.t_assert((select coalesce(sum(credit - debit), 0) from voucher_lines where account_id = :'acc_ap') = 0, 'AP nets to zero after bill reversal');
select 'GRNI balance', coalesce(sum(credit - debit), 0) from voucher_lines where account_id = :'acc_grni';
set role authenticated;

\echo '== 13. permissions and RLS'
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', false);
select public.t_assert((select count(*) from trade_documents where doc_type = 'purchase_order') = 0, 'employee cannot see purchase orders');
select public.t_expect_error(format($q$select public.save_purchase_document(gen_random_uuid(), %L, 'purchase_order', %L, current_date, null, null, null, null, null, null, null, null,
  jsonb_build_array(jsonb_build_object('product_id', %L, 'quantity', 1, 'unit_price', 1)))$q$, :'org', :'s1', :'p1'), 'permission');
select public.t_expect_error($q$select * from stock_summary((select org_id from organization_members where user_id = auth.uid() limit 1))$q$, 'Access denied');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);
select public.save_purchase_document(gen_random_uuid(), :'org', 'goods_receipt', :'s2', current_date, null, null, null, :'wh', null, null, null, null,
  jsonb_build_array(jsonb_build_object('product_id', :'p1', 'quantity', 1, 'unit_price', 12))) as grn_draft \gset
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', false);
select public.t_expect_error(format($q$select public.post_goods_receipt(%L)$q$, :'grn_draft'), 'permission');
select public.t_expect_error(format($q$select public.save_stock_adjustment(gen_random_uuid(), %L, current_date, %L, 'lost', null,
  jsonb_build_array(jsonb_build_object('product_id', %L, 'quantity_change', -1)))$q$, :'org', :'wh', :'p1'), 'permission');
select public.t_expect_error(format($q$insert into trade_documents (org_id, doc_type, number) values (%L, 'purchase_order', 'X-1')$q$, :'org'), 'row-level security');
select public.t_assert(public.t_rows(format($q$update stock_balances set quantity = 999 where org_id = %L$q$, :'org')) = 0, 'app users cannot change balances');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', false);
select public.t_assert((select count(*) from stock_movements) = 0, 'store manager (no financial data) cannot read movements directly');
select public.t_assert((select count(*) from stock_summary(:'org')) >= 2, 'store manager can read the stock summary');
select public.t_assert((select bool_and(value is null and avg_cost is null) from stock_summary(:'org')), 'stock summary hides values from store manager');
select public.t_assert((select bool_and(unit_cost is null and value is null) from stock_ledger(:'org', :'p1')), 'ledger hides cost from store manager');
select public.t_assert((select count(*) from stock_on_hand(:'org')) >= 2, 'stock on hand visible');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);
select public.t_assert((select bool_and(value is not null) from stock_summary(:'org')), 'owner sees values');
select public.t_assert((select count(*) from stock_ledger(:'org', :'p1')) >= 5, 'ledger has movements');
select public.t_assert((select running_qty from stock_ledger(:'org', :'p1') limit 1) = 55, 'latest running qty is current stock');
select public.t_assert((select unit_cost from last_purchase_prices(:'org') where product_id = :'p1') = 12, 'last purchase price of widget is 12');

\echo '== 14. cancel and discard paths, related documents'
select public.save_purchase_document(gen_random_uuid(), :'org', 'purchase_order', :'s2', current_date, null, null, null, :'wh', null, null, null, :'req',
  jsonb_build_array(jsonb_build_object('product_id', :'p1', 'quantity', 5, 'unit_price', 10))) as po2 \gset
select public.t_assert((select count(*) from related_documents(:'req')) = 2, 'requisition links to its two orders');
select public.discard_document(:'po2');
select public.t_assert((select status from trade_documents where id = :'req') = 'ordered', 'still ordered by first PO');
select public.t_assert((select count(*) from related_documents(:'po') where doc_type = 'goods_receipt') = 2 , 'po links to its live receipts');
select public.t_assert((select count(*) from related_documents(:'po') where doc_type = 'purchase_requisition') = 1, 'po links to requisition');
select public.save_purchase_document(gen_random_uuid(), :'org', 'purchase_order', :'s2', current_date, null, null, null, :'wh', null, null, null, null,
  jsonb_build_array(jsonb_build_object('product_id', :'p1', 'quantity', 5, 'unit_price', 10))) as po3 \gset
select public.submit_document(:'po3');
select public.reject_document(:'po3', 'Price too high');
select public.t_assert((select status from trade_documents where id = :'po3') = 'rejected', 'po rejected');
select public.save_purchase_document(:'po3', :'org', 'purchase_order', :'s2', current_date, null, null, null, :'wh', null, null, null, null,
  jsonb_build_array(jsonb_build_object('product_id', :'p1', 'quantity', 5, 'unit_price', 9))) ;
select public.t_assert((select status from trade_documents where id = :'po3') = 'draft', 'edited rejected po goes back to draft');
select public.cancel_document(:'po3', 'No longer needed');
select public.t_assert((select status from trade_documents where id = :'po3') = 'cancelled', 'po cancelled');
select public.close_purchase_order(:'po', 'Rest not needed');
select public.t_assert((select status from trade_documents where id = :'po') = 'closed', 'po closed');
reset role;
select public.t_assert((select count(*) from audit_logs where table_name = 'trade_documents') > 0, 'trade documents are audited');
select public.t_assert((select count(*) from audit_logs where table_name = 'stock_adjustments') > 0, 'adjustments are audited');

\echo 'ALL TESTS PASSED'
