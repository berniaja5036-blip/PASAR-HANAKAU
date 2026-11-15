\set ON_ERROR_STOP on
do $$ begin create role authenticated nologin; exception when duplicate_object then null; end $$;
do $$ begin create role anon nologin; exception when duplicate_object then null; end $$;
do $$ begin create role service_role nologin bypassrls; exception when duplicate_object then null; end $$;

create schema if not exists auth;
create or replace function auth.uid()
returns uuid language sql stable
as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
grant usage on schema auth to authenticated, anon;
grant execute on function auth.uid() to authenticated, anon;

create table public.profiles (
  id uuid primary key,
  role text not null check (role in ('buyer','seller','driver','admin')),
  account_status text not null default 'active',
  created_at timestamptz not null default now()
);
create table public.shops (
  id uuid primary key,
  owner_id uuid not null references public.profiles(id),
  status text not null,
  created_at timestamptz not null default now()
);
create table public.seller_applications (
  id uuid primary key,
  user_id uuid not null references public.profiles(id),
  status text not null,
  reviewed_by uuid,
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);
create table public.driver_profiles (
  id uuid primary key references public.profiles(id),
  approval_status text not null
);
create table public.driver_applications (
  id uuid primary key,
  user_id uuid not null references public.profiles(id),
  status text not null,
  reviewed_by uuid,
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);

create or replace function public.is_admin()
returns boolean language sql stable security definer
set search_path = pg_catalog, public
as $$ select exists (
  select 1 from public.profiles p
  where p.id=(select auth.uid()) and p.role='admin' and p.account_status='active'
) $$;
grant execute on function public.is_admin() to authenticated;

insert into public.profiles(id,role,account_status) values
('00000000-0000-0000-0000-000000000001','buyer','active'),
('00000000-0000-0000-0000-000000000002','seller','active'),
('00000000-0000-0000-0000-000000000003','driver','active'),
('00000000-0000-0000-0000-000000000004','admin','active'),
('00000000-0000-0000-0000-000000000005','buyer','active'),
('00000000-0000-0000-0000-000000000006','buyer','suspended');

insert into public.shops(id,owner_id,status) values
('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002','approved');
insert into public.seller_applications(id,user_id,status,reviewed_by,reviewed_at) values
('20000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002','approved','00000000-0000-0000-0000-000000000004',now());

insert into public.driver_profiles(id,approval_status) values
('00000000-0000-0000-0000-000000000003','approved');
insert into public.driver_applications(id,user_id,status,reviewed_by,reviewed_at) values
('30000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000003','approved','00000000-0000-0000-0000-000000000004',now()),
('30000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000005','pending',null,null);
