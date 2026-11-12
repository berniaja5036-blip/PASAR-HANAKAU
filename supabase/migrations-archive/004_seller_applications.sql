-- Pasar Hanakau: pengajuan toko penjual dengan persetujuan admin.
create table if not exists public.seller_applications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references public.profiles(id) on delete cascade,
  shop_name text not null check (length(trim(shop_name)) between 2 and 100),
  shop_description text,
  shop_address text not null check (length(trim(shop_address)) between 5 and 300),
  contact_phone text,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);
alter table public.seller_applications enable row level security;
grant select, insert on public.seller_applications to authenticated;
grant update (status, reviewed_by, reviewed_at) on public.seller_applications to authenticated;

drop policy if exists seller_applications_read_own_or_admin on public.seller_applications;
create policy seller_applications_read_own_or_admin
on public.seller_applications for select to authenticated
using (user_id = (select auth.uid()) or (select public.is_admin()));

drop policy if exists seller_applications_insert_own on public.seller_applications;
create policy seller_applications_insert_own
on public.seller_applications for insert to authenticated
with check (user_id = (select auth.uid()) and status = 'pending');

drop policy if exists seller_applications_admin_update on public.seller_applications;
create policy seller_applications_admin_update
on public.seller_applications for update to authenticated
using ((select public.is_admin()))
with check ((select public.is_admin()));

create or replace function public.approve_seller_application(application_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  application_row public.seller_applications%rowtype;
  new_shop_id uuid;
begin
  if not public.is_admin() then
    raise exception 'Hanya admin yang dapat menyetujui pengajuan toko';
  end if;

  select * into application_row
  from public.seller_applications
  where id = application_id
  for update;

  if not found then
    raise exception 'Pengajuan toko tidak ditemukan';
  end if;
  if application_row.status <> 'pending' then
    raise exception 'Pengajuan ini sudah diproses';
  end if;

  update public.profiles set role = 'seller'
  where id = application_row.user_id;

  insert into public.shops (owner_id, name, description, address, status)
  values (application_row.user_id, application_row.shop_name,
          application_row.shop_description, application_row.shop_address, 'approved')
  returning id into new_shop_id;

  update public.seller_applications
  set status = 'approved', reviewed_by = auth.uid(), reviewed_at = now()
  where id = application_row.id;

  return new_shop_id;
end;
$$;

revoke all on function public.approve_seller_application(uuid) from public;
grant execute on function public.approve_seller_application(uuid) to authenticated;
