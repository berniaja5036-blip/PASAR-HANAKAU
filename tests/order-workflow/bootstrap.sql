\set ON_ERROR_STOP on

-- Isolated fixture for exercising the production workflow functions.
-- This database is created by the GitHub Actions PostgreSQL service only.
create schema if not exists storage;

create or replace function public.is_admin()
returns boolean
language sql
stable
set search_path = pg_catalog
as $$
  select coalesce(current_setting('test.is_admin', true), 'false') = 'true';
$$;

create or replace function storage.foldername(p_name text)
returns text[]
language sql
immutable
set search_path = pg_catalog
as $$
  select case
    when pg_catalog.strpos(p_name, '/') = 0 then array[]::text[]
    else pg_catalog.string_to_array(
      pg_catalog.regexp_replace(p_name, '/[^/]*$', ''),
      '/'
    )
  end;
$$;

create table public.profiles (
  id uuid primary key,
  role text not null,
  account_status text not null
);

create table public.driver_profiles (
  id uuid primary key,
  approval_status text not null
);

create table public.driver_applications (
  user_id uuid primary key,
  status text not null,
  ktp_image_path text,
  face_image_path text
);

create table storage.objects (
  bucket_id text not null,
  name text not null,
  primary key (bucket_id, name)
);

create table public.orders (
  id uuid primary key,
  status text not null
);

create table public.deliveries (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null unique references public.orders(id),
  status text not null,
  driver_id uuid,
  assigned_at timestamptz,
  delivery_notes text
);

create table public.products (
  id uuid primary key,
  stock integer not null
);

create table public.order_items (
  order_id uuid not null references public.orders(id),
  product_id uuid,
  quantity integer not null
);

create table public.order_cancellation_requests (
  order_id uuid not null references public.orders(id),
  status text not null
);
