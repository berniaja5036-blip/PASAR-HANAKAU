\set ON_ERROR_STOP on

create schema if not exists auth;

create role anon nologin;
create role authenticated nologin;

create table public.profiles (
  id uuid primary key,
  role text not null,
  account_status text not null
);

create table public.shops (
  id uuid primary key,
  owner_id uuid not null references public.profiles(id)
);

create table public.orders (
  id uuid primary key,
  order_number text not null,
  status text not null,
  created_at timestamptz not null,
  notes text,
  delivery_address text,
  delivery_latitude numeric,
  delivery_longitude numeric
);

create table public.order_items (
  id uuid primary key,
  order_id uuid not null references public.orders(id),
  shop_id uuid not null references public.shops(id),
  product_name text not null,
  quantity integer not null,
  unit_price numeric not null,
  line_total numeric not null,
  created_at timestamptz not null
);

create table public.order_status_history (
  id uuid primary key,
  order_id uuid not null references public.orders(id),
  from_status text,
  to_status text not null,
  changed_at timestamptz not null
);

create or replace function auth.uid()
returns uuid
language sql
stable
set search_path = pg_catalog
as $test$
  select nullif(current_setting('test.user_id', true), '')::uuid;
$test$;

create or replace function public.current_user_has_role(required_role text)
returns boolean
language sql
stable
set search_path = pg_catalog
as $test$
  select exists (
    select 1
    from public.profiles as p
    where p.id = auth.uid()
      and p.role = required_role
      and p.account_status = 'active'
  );
$test$;
