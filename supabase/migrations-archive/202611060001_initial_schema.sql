-- Pasar Hanakau: initial database schema
-- Apply in a fresh Supabase project using the SQL Editor.
-- Do not expose service-role keys in the browser.

create extension if not exists pgcrypto;

create type public.account_role as enum ('buyer', 'seller', 'driver', 'admin');
create type public.approval_status as enum ('pending', 'approved', 'rejected', 'suspended');
create type public.product_status as enum ('draft', 'active', 'hidden', 'rejected');
create type public.order_status as enum ('placed', 'accepted', 'pickup_assigned', 'picked_up', 'delivered', 'cancelled');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  phone text,
  village text not null default 'Hanakau Jaya',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.role_memberships (
  user_id uuid not null references auth.users(id) on delete cascade,
  role public.account_role not null,
  status public.approval_status not null default 'approved',
  created_at timestamptz not null default now(),
  primary key (user_id, role)
);

create table public.stores (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id),
  name text not null,
  description text not null default '',
  address text not null,
  phone text,
  status public.approval_status not null default 'pending',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.products (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  name text not null,
  description text not null default '',
  price_idr bigint not null check (price_idr >= 0),
  stock integer not null default 0 check (stock >= 0),
  image_path text,
  status public.product_status not null default 'draft',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  order_number text not null unique,
  buyer_id uuid not null references auth.users(id),
  delivery_address text not null,
  notes text not null default '',
  status public.order_status not null default 'placed',
  subtotal_idr bigint not null check (subtotal_idr >= 0),
  delivery_fee_idr bigint not null default 0 check (delivery_fee_idr >= 0),
  total_idr bigint generated always as (subtotal_idr + delivery_fee_idr) stored,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  product_id uuid references public.products(id) on delete set null,
  store_id uuid not null references public.stores(id),
  product_name_snapshot text not null,
  unit_price_idr bigint not null check (unit_price_idr >= 0),
  quantity integer not null check (quantity > 0),
  line_total_idr bigint generated always as (unit_price_idr * quantity) stored
);

create table public.delivery_tasks (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null unique references public.orders(id) on delete cascade,
  driver_id uuid references auth.users(id),
  pickup_address text not null,
  delivery_address text not null,
  status text not null default 'unassigned'
    check (status in ('unassigned','assigned','picked_up','delivered','cancelled')),
  assigned_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.order_status_events (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  changed_by uuid references auth.users(id),
  old_status public.order_status,
  new_status public.order_status not null,
  note text not null default '',
  created_at timestamptz not null default now()
);

create index stores_owner_idx on public.stores(owner_id);
create index products_store_status_idx on public.products(store_id, status);
create index orders_buyer_created_idx on public.orders(buyer_id, created_at desc);
create index delivery_tasks_driver_idx on public.delivery_tasks(driver_id, status);

create or replace function public.has_role(required_role public.account_role)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.role_memberships rm
    where rm.user_id = (select auth.uid())
      and rm.role = required_role
      and rm.status = 'approved'
  );
$$;

create or replace function public.is_store_owner(target_store uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.stores s
    where s.id = target_store and s.owner_id = (select auth.uid())
  );
$$;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name, phone)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    nullif(new.raw_user_meta_data ->> 'phone', '')
  );
  insert into public.role_memberships (user_id, role, status)
  values (new.id, 'buyer', 'approved');
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

alter table public.profiles enable row level security;
alter table public.role_memberships enable row level security;
alter table public.stores enable row level security;
alter table public.products enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.delivery_tasks enable row level security;
alter table public.order_status_events enable row level security;

create policy "profile owner or admin reads profiles"
on public.profiles for select to authenticated
using (id = (select auth.uid()) or public.has_role('admin'));

create policy "profile owner updates own basic profile"
on public.profiles for update to authenticated
using (id = (select auth.uid()))
with check (id = (select auth.uid()));

create policy "users read own roles; admins read all"
on public.role_memberships for select to authenticated
using (user_id = (select auth.uid()) or public.has_role('admin'));

-- No client-side insert/update/delete policy on role_memberships.
-- Assign seller/driver/admin roles only from a trusted server-side admin workflow.

create policy "approved stores are public; owner or admin reads own"
on public.stores for select
using (status = 'approved' or owner_id = (select auth.uid()) or public.has_role('admin'));

create policy "seller creates own pending store"
on public.stores for insert to authenticated
with check (owner_id = (select auth.uid()) and status = 'pending' and public.has_role('seller'));

create policy "owner edits own pending or approved store"
on public.stores for update to authenticated
using (owner_id = (select auth.uid()) or public.has_role('admin'))
with check (owner_id = (select auth.uid()) or public.has_role('admin'));

create policy "approved products public; owner/admin reads own"
on public.products for select
using (
  status = 'active'
  or public.is_store_owner(store_id)
  or public.has_role('admin')
);

create policy "approved seller adds draft product to own approved store"
on public.products for insert to authenticated
with check (
  status = 'draft'
  and public.is_store_owner(store_id)
  and public.has_role('seller')
  and exists (select 1 from public.stores s where s.id = store_id and s.status = 'approved')
);

create policy "seller edits own product; admin moderates"
on public.products for update to authenticated
using (public.is_store_owner(store_id) or public.has_role('admin'))
with check (public.is_store_owner(store_id) or public.has_role('admin'));

create policy "buyer reads own orders; admin reads all"
on public.orders for select to authenticated
using (buyer_id = (select auth.uid()) or public.has_role('admin'));

create policy "buyer creates own placed order"
on public.orders for insert to authenticated
with check (
  buyer_id = (select auth.uid())
  and status = 'placed'
);

create policy "seller or admin reads items for their orders"
on public.order_items for select to authenticated
using (
  public.has_role('admin')
  or exists (select 1 from public.orders o where o.id = order_id and o.buyer_id = (select auth.uid()))
  or public.is_store_owner(store_id)
);

create policy "buyer or admin reads delivery tasks; assigned driver reads own"
on public.delivery_tasks for select to authenticated
using (
  public.has_role('admin')
  or driver_id = (select auth.uid())
  or exists (select 1 from public.orders o where o.id = order_id and o.buyer_id = (select auth.uid()))
);

create policy "order participants read status history"
on public.order_status_events for select to authenticated
using (
  public.has_role('admin')
  or exists (select 1 from public.orders o where o.id = order_id and o.buyer_id = (select auth.uid()))
);

-- Deliberately no client write policies for order_items, delivery_tasks,
-- or order_status_events. Create these through validated server-side functions.
-- Before launch, add transactional checkout and admin assignment RPCs,
-- audit logging, payment provider webhook verification, and full RLS tests.

comment on table public.role_memberships is
  'Role changes are privileged server-side operations; never allow self-service role escalation.';
comment on table public.orders is
  'Checkout must be implemented as a server-side transaction that validates stock and prices.';
