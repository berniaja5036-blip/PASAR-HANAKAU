\set ON_ERROR_STOP on

insert into public.profiles(id, role, account_status) values
  ('30000000-0000-4000-8000-000000000001', 'seller', 'active'),
  ('30000000-0000-4000-8000-000000000002', 'seller', 'active'),
  ('30000000-0000-4000-8000-000000000003', 'seller', 'suspended'),
  ('30000000-0000-4000-8000-000000000004', 'buyer', 'active');

insert into public.shops(id, owner_id) values
  ('40000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001'),
  ('40000000-0000-4000-8000-000000000002', '30000000-0000-4000-8000-000000000002');

-- 120 seller-A orders share a timestamp to exercise the UUID tie-breaker.
insert into public.orders(id, order_number, status, created_at, notes, delivery_address, delivery_latitude, delivery_longitude)
select
  ('10000000-0000-4000-8000-' || lpad(g::text, 12, '0'))::uuid,
  'HK-' || lpad(g::text, 6, '0'),
  'pending',
  '2026-11-01T00:00:00Z'::timestamptz,
  'Catatan pembeli',
  'ALAMAT-PRIBADI-TIDAK-BOLEH-KELUAR',
  -4.8,
  104.8
from generate_series(1, 120) as g;

insert into public.order_items(id, order_id, shop_id, product_name, quantity, unit_price, line_total, created_at)
select
  ('50000000-0000-4000-8000-' || lpad(g::text, 12, '0'))::uuid,
  ('10000000-0000-4000-8000-' || lpad(g::text, 12, '0'))::uuid,
  '40000000-0000-4000-8000-000000000001',
  'Produk Penjual A ' || g,
  1,
  1000,
  1000,
  '2026-11-01T00:00:00Z'::timestamptz
from generate_series(1, 120) as g;

insert into public.order_status_history(id, order_id, from_status, to_status, changed_at)
select
  ('60000000-0000-4000-8000-' || lpad(g::text, 12, '0'))::uuid,
  ('10000000-0000-4000-8000-' || lpad(g::text, 12, '0'))::uuid,
  null,
  'pending',
  '2026-11-01T00:00:00Z'::timestamptz
from generate_series(1, 120) as g;

-- Two older orders for seller B, plus one shared order with distinct shop lines.
insert into public.orders(id, order_number, status, created_at, notes, delivery_address, delivery_latitude, delivery_longitude) values
  ('20000000-0000-4000-8000-000000000001', 'HK-B-0001', 'pending', '2026-10-01T00:00:00Z', null, 'RAHASIA', -4.8, 104.8),
  ('20000000-0000-4000-8000-000000000002', 'HK-B-0002', 'pending', '2026-10-02T00:00:00Z', null, 'RAHASIA', -4.8, 104.8),
  ('30000000-0000-4000-8000-000000000001', 'HK-SHARED', 'pending', '2026-09-01T00:00:00Z', null, 'RAHASIA', -4.8, 104.8);

insert into public.order_items(id, order_id, shop_id, product_name, quantity, unit_price, line_total, created_at) values
  ('50000000-0000-4000-8000-000000000121', '20000000-0000-4000-8000-000000000001', '40000000-0000-4000-8000-000000000002', 'Produk Penjual B 1', 1, 2000, 2000, '2026-10-01T00:00:00Z'),
  ('50000000-0000-4000-8000-000000000122', '20000000-0000-4000-8000-000000000002', '40000000-0000-4000-8000-000000000002', 'Produk Penjual B 2', 2, 2000, 4000, '2026-10-02T00:00:00Z'),
  ('50000000-0000-4000-8000-000000000123', '30000000-0000-4000-8000-000000000001', '40000000-0000-4000-8000-000000000001', 'Barang milik A', 1, 1000, 1000, '2026-09-01T00:00:00Z'),
  ('50000000-0000-4000-8000-000000000124', '30000000-0000-4000-8000-000000000001', '40000000-0000-4000-8000-000000000002', 'Barang milik B', 1, 2000, 2000, '2026-09-01T00:00:00Z');

select set_config('test.user_id', '30000000-0000-4000-8000-000000000001', false);

do $test$
declare
  v_cursor_created_at timestamptz;
  v_cursor_id uuid;
  v_page2_cursor_created_at timestamptz;
  v_page2_cursor_id uuid;
  v_count integer;
  v_has_more boolean;
begin
  select count(*), bool_and(has_more)
    into v_count, v_has_more
  from public.seller_list_orders_page(null, null, 50);
  if v_count <> 50 or not v_has_more then
    raise exception 'Page 1 should return 50 rows and has_more=true; got count %, has_more %.', v_count, v_has_more;
  end if;

  select created_at, id into v_cursor_created_at, v_cursor_id
  from public.seller_list_orders_page(null, null, 50)
  order by created_at desc, id desc
  offset 49 limit 1;

  select count(*), bool_and(has_more)
    into v_count, v_has_more
  from public.seller_list_orders_page(v_cursor_created_at, v_cursor_id, 50);
  if v_count <> 50 or not v_has_more then
    raise exception 'Page 2 should return 50 rows and has_more=true; got count %, has_more %.', v_count, v_has_more;
  end if;

  select created_at, id into v_page2_cursor_created_at, v_page2_cursor_id
  from public.seller_list_orders_page(v_cursor_created_at, v_cursor_id, 50)
  order by created_at desc, id desc
  offset 49 limit 1;

  select count(*), bool_and(has_more)
    into v_count, v_has_more
  from public.seller_list_orders_page(v_page2_cursor_created_at, v_page2_cursor_id, 50);
  if v_count <> 21 or coalesce(v_has_more, true) then
    raise exception 'Page 3 should return 21 rows and has_more=false; got count %, has_more %.', v_count, v_has_more;
  end if;

  if (select count(*) from (
    select id from public.seller_list_orders_page(null, null, 50)
    union all
    select id from public.seller_list_orders_page(v_cursor_created_at, v_cursor_id, 50)
    union all
    select id from public.seller_list_orders_page(v_page2_cursor_created_at, v_page2_cursor_id, 50)
  ) as pages) <> 121 then
    raise exception 'Three pages should contain exactly 121 distinct seller-A orders without gaps.';
  end if;

  if exists (
    select id from (
      select id from public.seller_list_orders_page(null, null, 50)
      intersect
      select id from public.seller_list_orders_page(v_cursor_created_at, v_cursor_id, 50)
    ) as overlap
  ) then
    raise exception 'Page 1 and page 2 overlap.';
  end if;

  if (select id from public.seller_list_orders_page(null, null, 50) order by created_at desc, id desc limit 1)
     <> '10000000-0000-4000-8000-000000000120'::uuid then
    raise exception 'The UUID tie-breaker did not put the newest stable order first.';
  end if;

end;
$test$;

-- Seller A sees only its own line in a shared order; seller B sees only its own line.
do $test$
declare
  v_items jsonb;
begin
  -- The cursor after the last seller-A order reaches the older shared order.
  select order_items into v_items
  from public.seller_list_orders_page('2026-11-01T00:00:00Z', '10000000-0000-4000-8000-000000000001', 50)
  where order_number = 'HK-SHARED';

  if v_items is null or v_items::text not like '%Barang milik A%' or v_items::text like '%Barang milik B%' then
    raise exception 'Seller A received a shared-order line belonging to another shop.';
  end if;
end;
$test$;

select set_config('test.user_id', '30000000-0000-4000-8000-000000000002', false);

do $test$
declare
  v_count integer;
  v_items jsonb;
begin
  select count(*) into v_count
  from public.seller_list_orders_page(null, null, 50);
  if v_count <> 3 then
    raise exception 'Seller B should see two private orders and one shared order; got %.', v_count;
  end if;

  select order_items into v_items
  from public.seller_list_orders_page(null, null, 50)
  where order_number = 'HK-SHARED';
  if v_items is null or v_items::text not like '%Barang milik B%' or v_items::text like '%Barang milik A%' then
    raise exception 'Seller B received a shared-order line belonging to another shop.';
  end if;
end;
$test$;

-- The RPC must not expose delivery address/coordinates and must remain SECURITY DEFINER with an empty search_path.
do $test$
declare
  v_result text;
  v_is_security_definer boolean;
  v_settings text[];
begin
  select pg_get_function_result(p.oid), p.prosecdef, p.proconfig
    into v_result, v_is_security_definer, v_settings
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'seller_list_orders_page';

  if v_result ilike '%delivery_address%' or v_result ilike '%latitude%' or v_result ilike '%longitude%' then
    raise exception 'Seller pagination RPC exposes buyer delivery location fields.';
  end if;
  if not v_is_security_definer or not ('search_path=""' = any(v_settings)) then
    raise exception 'Seller pagination RPC must be SECURITY DEFINER with an empty search_path.';
  end if;
  if has_function_privilege('anon', 'public.seller_list_orders_page(timestamp with time zone,uuid,integer)', 'EXECUTE') then
    raise exception 'anon unexpectedly has execute permission on seller pagination RPC.';
  end if;
  if not has_function_privilege('authenticated', 'public.seller_list_orders_page(timestamp with time zone,uuid,integer)', 'EXECUTE') then
    raise exception 'authenticated is missing execute permission on seller pagination RPC.';
  end if;
end;
$test$;

-- Invalid page sizes and partial cursors must fail closed.
do $test$
declare
  v_error text;
begin
  v_error := null;
  begin
    perform * from public.seller_list_orders_page(null, null, 0);
  exception when others then v_error := sqlerrm;
  end;
  if v_error is null then raise exception 'Page size 0 was accepted.'; end if;

  v_error := null;
  begin
    perform * from public.seller_list_orders_page(null, null, 51);
  exception when others then v_error := sqlerrm;
  end;
  if v_error is null then raise exception 'Page size 51 was accepted.'; end if;

  v_error := null;
  begin
    perform * from public.seller_list_orders_page('2026-11-01T00:00:00Z', null, 50);
  exception when others then v_error := sqlerrm;
  end;
  if v_error is null then raise exception 'An incomplete cursor was accepted.'; end if;
end;
$test$;

-- A buyer, suspended seller, or unauthenticated session cannot use the RPC.
select set_config('test.user_id', '30000000-0000-4000-8000-000000000004', false);
do $test$
declare v_error text;
begin
  begin
    perform * from public.seller_list_orders_page(null, null, 50);
  exception when others then v_error := sqlerrm;
  end;
  if v_error is null or v_error not like '%Akun penjual aktif%' then
    raise exception 'Buyer was not rejected by the seller RPC.';
  end if;
end;
$test$;

select set_config('test.user_id', '30000000-0000-4000-8000-000000000003', false);
do $test$
declare v_error text;
begin
  begin
    perform * from public.seller_list_orders_page(null, null, 50);
  exception when others then v_error := sqlerrm;
  end;
  if v_error is null or v_error not like '%Akun penjual aktif%' then
    raise exception 'Suspended seller was not rejected by the seller RPC.';
  end if;
end;
$test$;

select set_config('test.user_id', '', false);
do $test$
declare v_error text;
begin
  begin
    perform * from public.seller_list_orders_page(null, null, 50);
  exception when others then v_error := sqlerrm;
  end;
  if v_error is null or v_error not like '%Silakan masuk%' then
    raise exception 'Unauthenticated session was not rejected by the seller RPC.';
  end if;
end;
$test$;
