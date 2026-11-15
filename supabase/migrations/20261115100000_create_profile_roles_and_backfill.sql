begin;

create table public.profile_roles (
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null check (role in ('buyer','seller','driver','admin')),
  status text not null default 'pending' check (status in ('active','pending','suspended','rejected')),
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  approved_at timestamptz,
  approved_by uuid references public.profiles(id) on delete set null,
  constraint profile_roles_pkey primary key (user_id, role)
);

comment on table public.profile_roles is
  'Authoritative multi-role assignments. profiles.role remains a legacy primary-role field during migration.';
comment on column public.profile_roles.status is
  'Role-specific state. Account-wide suspension remains controlled by profiles.account_status.';

create index profile_roles_role_status_idx
  on public.profile_roles (role, status);
create index profile_roles_user_status_idx
  on public.profile_roles (user_id, status);

alter table public.profile_roles enable row level security;

revoke all on table public.profile_roles from public, anon, authenticated;
grant select on table public.profile_roles to authenticated;
grant select, insert, update, delete on table public.profile_roles to service_role;

create policy profile_roles_select_self_or_admin
  on public.profile_roles
  for select
  to authenticated
  using (user_id = (select auth.uid()) or public.is_admin());

-- Every non-admin account retains buyer access. The legacy primary role is
-- preserved and is not changed by this migration.
insert into public.profile_roles (user_id, role, status)
select p.id, 'buyer', 'active'
from public.profiles p
where p.role <> 'admin'
on conflict (user_id, role) do nothing;

insert into public.profile_roles (user_id, role, status)
select p.id, 'admin', 'active'
from public.profiles p
where p.role = 'admin'
on conflict (user_id, role) do nothing;

-- Backfill the latest seller application per user. Approval is active only
-- when an approved shop exists; an inconsistent approval remains pending.
with latest_seller_application as (
  select distinct on (a.user_id)
    a.user_id, a.status, a.reviewed_at, a.reviewed_by
  from public.seller_applications a
  order by a.user_id, a.created_at desc, a.id desc
)
insert into public.profile_roles (user_id, role, status, approved_at, approved_by)
select
  a.user_id,
  'seller',
  case
    when a.status = 'approved' and exists (
      select 1 from public.shops s
      where s.owner_id = a.user_id and s.status = 'approved'
    ) then 'active'
    when a.status = 'rejected' then 'rejected'
    else 'pending'
  end,
  case when a.status = 'approved' and exists (
    select 1 from public.shops s
    where s.owner_id = a.user_id and s.status = 'approved'
  ) then a.reviewed_at else null end,
  case when a.status = 'approved' and exists (
    select 1 from public.shops s
    where s.owner_id = a.user_id and s.status = 'approved'
  ) then a.reviewed_by else null end
from latest_seller_application a
on conflict (user_id, role) do update
set status = excluded.status,
    approved_at = excluded.approved_at,
    approved_by = excluded.approved_by,
    updated_at = pg_catalog.now();

-- A previously approved driver remains active when the application and
-- driver profile are approved. Historical document-path gaps are not used
-- to silently revoke an existing approved role; assignment RPCs retain their
-- separate document-object checks.
with latest_driver_application as (
  select distinct on (a.user_id)
    a.user_id, a.status, a.reviewed_at, a.reviewed_by
  from public.driver_applications a
  order by a.user_id, a.created_at desc, a.id desc
)
insert into public.profile_roles (user_id, role, status, approved_at, approved_by)
select
  a.user_id,
  'driver',
  case
    when a.status = 'approved' and exists (
      select 1 from public.driver_profiles d
      where d.id = a.user_id and d.approval_status = 'approved'
    ) then 'active'
    when a.status = 'rejected' then 'rejected'
    else 'pending'
  end,
  case when a.status = 'approved' and exists (
    select 1 from public.driver_profiles d
    where d.id = a.user_id and d.approval_status = 'approved'
  ) then a.reviewed_at else null end,
  case when a.status = 'approved' and exists (
    select 1 from public.driver_profiles d
    where d.id = a.user_id and d.approval_status = 'approved'
  ) then a.reviewed_by else null end
from latest_driver_application a
on conflict (user_id, role) do update
set status = excluded.status,
    approved_at = excluded.approved_at,
    approved_by = excluded.approved_by,
    updated_at = pg_catalog.now();

create or replace function public.sync_profile_role_from_profile()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
begin
  if tg_op = 'UPDATE' and old.role = 'admin' and new.role <> 'admin' then
    update public.profile_roles
    set status = 'suspended', updated_at = pg_catalog.now()
    where user_id = new.id and role = 'admin';
  end if;

  if new.role = 'admin' then
    insert into public.profile_roles (user_id, role, status)
    values (new.id, 'admin', 'active')
    on conflict (user_id, role) do update
      set status = 'active', updated_at = pg_catalog.now();
  elsif new.role = 'buyer' then
    insert into public.profile_roles (user_id, role, status)
    values (new.id, 'buyer', 'active')
    on conflict (user_id, role) do update
      set status = 'active', updated_at = pg_catalog.now();
  end if;
  return new;
end;
$function$;

create trigger profiles_sync_profile_roles
  after insert or update of role on public.profiles
  for each row execute function public.sync_profile_role_from_profile();

create or replace function public.sync_seller_application_profile_role()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_role_status text;
  v_approved boolean;
begin
  v_approved := new.status = 'approved' and exists (
    select 1 from public.shops s
    where s.owner_id = new.user_id and s.status = 'approved'
  );
  v_role_status := case
    when v_approved then 'active'
    when new.status = 'rejected' then 'rejected'
    else 'pending'
  end;

  insert into public.profile_roles (user_id, role, status, approved_at, approved_by)
  values (
    new.user_id, 'seller', v_role_status,
    case when v_approved then new.reviewed_at else null end,
    case when v_approved then new.reviewed_by else null end
  )
  on conflict (user_id, role) do update
    set status = excluded.status,
        approved_at = excluded.approved_at,
        approved_by = excluded.approved_by,
        updated_at = pg_catalog.now();
  return new;
end;
$function$;

create trigger seller_applications_sync_profile_role
  after insert or update of status on public.seller_applications
  for each row execute function public.sync_seller_application_profile_role();

create or replace function public.sync_driver_application_profile_role()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_role_status text;
  v_approved boolean;
begin
  v_approved := new.status = 'approved' and exists (
    select 1 from public.driver_profiles d
    where d.id = new.user_id and d.approval_status = 'approved'
  );
  v_role_status := case
    when v_approved then 'active'
    when new.status = 'rejected' then 'rejected'
    else 'pending'
  end;

  insert into public.profile_roles (user_id, role, status, approved_at, approved_by)
  values (
    new.user_id, 'driver', v_role_status,
    case when v_approved then new.reviewed_at else null end,
    case when v_approved then new.reviewed_by else null end
  )
  on conflict (user_id, role) do update
    set status = excluded.status,
        approved_at = excluded.approved_at,
        approved_by = excluded.approved_by,
        updated_at = pg_catalog.now();
  return new;
end;
$function$;

create trigger driver_applications_sync_profile_role
  after insert or update of status on public.driver_applications
  for each row execute function public.sync_driver_application_profile_role();

create or replace function public.current_user_has_active_role(required_role text)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $function$
  select exists (
    select 1
    from public.profile_roles pr
    join public.profiles p on p.id = pr.user_id
    where pr.user_id = (select auth.uid())
      and pr.role = required_role
      and pr.status = 'active'
      and p.account_status = 'active'
  );
$function$;

revoke all on function public.sync_profile_role_from_profile() from public, anon, authenticated;
revoke all on function public.sync_seller_application_profile_role() from public, anon, authenticated;
revoke all on function public.sync_driver_application_profile_role() from public, anon, authenticated;
revoke all on function public.current_user_has_active_role(text) from public, anon;
grant execute on function public.current_user_has_active_role(text) to authenticated, service_role;

notify pgrst, 'reload schema';

commit;
