\set ON_ERROR_STOP on

create schema if not exists auth;
create role anon nologin;
create role authenticated nologin;
create role service_role nologin;

create or replace function auth.role()
returns text
language sql
stable
set search_path = pg_catalog
as $function$
  select nullif(pg_catalog.current_setting('request.jwt.claim.role', true), '');
$function$;

create table public.profiles (
  id uuid primary key
);

create table public.checkout_test_calls (
  call_count integer not null default 0
);
insert into public.checkout_test_calls(call_count) values (0);

-- Test double for the production voucher-aware checkout function.
-- It records how many times a new checkout transaction is actually invoked.
create or replace function public.checkout_cart_with_voucher_secure(
  p_buyer_id uuid,
  p_items jsonb,
  p_delivery_address text,
  p_notes text,
  p_delivery_latitude numeric,
  p_delivery_longitude numeric,
  p_delivery_fees jsonb,
  p_voucher_code text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_call integer;
begin
  update public.checkout_test_calls
     set call_count = call_count + 1
   returning call_count into v_call;

  return pg_catalog.jsonb_build_array(
    pg_catalog.jsonb_build_object('order_number', 'TEST-' || v_call)
  );
end;
$function$;
