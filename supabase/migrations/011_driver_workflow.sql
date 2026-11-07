-- Pasar Hanakau: pendaftaran, persetujuan, penugasan, dan alur kerja driver.
-- Jalankan sekali di Supabase SQL Editor setelah migrasi 010.

create table if not exists public.driver_applications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references public.profiles(id) on delete cascade,
  vehicle_type text not null check (length(trim(vehicle_type)) between 2 and 60),
  vehicle_plate text not null check (length(trim(vehicle_plate)) between 2 and 20),
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.driver_applications enable row level security;
grant select, insert on public.driver_applications to authenticated;

drop policy if exists driver_applications_read_own_or_admin on public.driver_applications;
create policy driver_applications_read_own_or_admin
on public.driver_applications for select to authenticated
using (user_id = (select auth.uid()) or (select public.is_admin()));

drop policy if exists driver_applications_insert_own on public.driver_applications;
create policy driver_applications_insert_own
on public.driver_applications for insert to authenticated
with check (user_id = (select auth.uid()) and status = 'pending');

grant select on public.driver_profiles, public.deliveries to authenticated;

-- Driver hanya dapat membaca pesanan dan barang yang memang ditugaskan kepadanya.
drop policy if exists orders_assigned_driver_read on public.orders;
create policy orders_assigned_driver_read
on public.orders for select to authenticated
using (
  exists (
    select 1 from public.deliveries d
    where d.order_id = orders.id and d.driver_id = (select auth.uid())
  )
);

drop policy if exists order_items_assigned_driver_read on public.order_items;
create policy order_items_assigned_driver_read
on public.order_items for select to authenticated
using (
  exists (
    select 1 from public.deliveries d
    where d.order_id = order_items.order_id and d.driver_id = (select auth.uid())
  )
);

create or replace function public.admin_review_driver_application(
  p_application_id uuid,
  p_approve boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_app public.driver_applications%rowtype;
begin
  if not coalesce(public.is_admin(), false) then
    raise exception 'Hanya admin yang dapat memproses pendaftaran driver.';
  end if;

  select * into v_app
  from public.driver_applications
  where id = p_application_id
  for update;

  if not found then
    raise exception 'Pendaftaran driver tidak ditemukan.';
  end if;
  if v_app.status <> 'pending' then
    raise exception 'Pendaftaran driver ini sudah diproses.';
  end if;

  if p_approve then
    update public.profiles set role = 'driver' where id = v_app.user_id;
    insert into public.driver_profiles (id, vehicle_type, vehicle_plate, approval_status)
    values (v_app.user_id, v_app.vehicle_type, v_app.vehicle_plate, 'approved')
    on conflict (id) do update
      set vehicle_type = excluded.vehicle_type,
          vehicle_plate = excluded.vehicle_plate,
          approval_status = 'approved';
    update public.driver_applications
       set status = 'approved', reviewed_by = (select auth.uid()), reviewed_at = now()
     where id = v_app.id;
  else
    update public.driver_applications
       set status = 'rejected', reviewed_by = (select auth.uid()), reviewed_at = now()
     where id = v_app.id;
  end if;
end;
$$;

revoke all on function public.admin_review_driver_application(uuid, boolean) from public, anon;
grant execute on function public.admin_review_driver_application(uuid, boolean) to authenticated;

create or replace function public.admin_assign_delivery(
  p_order_id uuid,
  p_driver_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order_status text;
  v_delivery_status text;
begin
  if not coalesce(public.is_admin(), false) then
    raise exception 'Hanya admin yang dapat menugaskan driver.';
  end if;

  if not exists (
    select 1 from public.driver_profiles dp
    where dp.id = p_driver_id and dp.approval_status = 'approved'
  ) then
    raise exception 'Akun driver belum disetujui atau tidak ditemukan.';
  end if;

  select status into v_order_status
  from public.orders where id = p_order_id for update;

  if not found then
    raise exception 'Pesanan tidak ditemukan.';
  end if;
  if v_order_status <> 'ready_for_pickup' then
    raise exception 'Pesanan harus berstatus Siap dijemput sebelum ditugaskan.';
  end if;

  select status into v_delivery_status
  from public.deliveries where order_id = p_order_id for update;

  if not found then
    raise exception 'Data pengiriman untuk pesanan ini tidak ditemukan.';
  end if;
  if v_delivery_status not in ('waiting','assigned') then
    raise exception 'Pengiriman sudah berjalan dan tidak dapat ditugaskan ulang.';
  end if;

  update public.deliveries
     set driver_id = p_driver_id, status = 'assigned', assigned_at = now()
   where order_id = p_order_id;
end;
$$;

revoke all on function public.admin_assign_delivery(uuid, uuid) from public, anon;
grant execute on function public.admin_assign_delivery(uuid, uuid) to authenticated;

create or replace function public.driver_update_delivery_status(
  p_delivery_id uuid,
  p_new_status text,
  p_note text default ''
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order_id uuid;
  v_delivery_status text;
  v_order_status text;
begin
  if (select auth.uid()) is null then
    raise exception 'Silakan masuk terlebih dahulu.';
  end if;
  if not exists (
    select 1 from public.driver_profiles dp
    where dp.id = (select auth.uid()) and dp.approval_status = 'approved'
  ) then
    raise exception 'Akun driver belum disetujui.';
  end if;
  if p_new_status not in ('picked_up','delivered') then
    raise exception 'Status pengiriman tidak valid.';
  end if;

  select d.order_id, d.status, o.status
    into v_order_id, v_delivery_status, v_order_status
  from public.deliveries d
  join public.orders o on o.id = d.order_id
  where d.id = p_delivery_id and d.driver_id = (select auth.uid())
  for update of d, o;

  if not found then
    raise exception 'Tugas pengiriman tidak ditemukan untuk akun driver ini.';
  end if;

  if p_new_status = 'picked_up' then
    if v_delivery_status <> 'assigned' or v_order_status <> 'ready_for_pickup' then
      raise exception 'Pesanan belum siap dijemput atau status tugas tidak sesuai.';
    end if;
    update public.deliveries
       set status = 'picked_up', picked_up_at = now(),
           pickup_notes = nullif(trim(coalesce(p_note,'')), '')
     where id = p_delivery_id;
    update public.orders set status = 'picked_up' where id = v_order_id;
  else
    if v_delivery_status <> 'picked_up' or v_order_status <> 'picked_up' then
      raise exception 'Pesanan harus dijemput terlebih dahulu.';
    end if;
    update public.deliveries
       set status = 'delivered', delivered_at = now(),
           delivery_notes = nullif(trim(coalesce(p_note,'')), '')
     where id = p_delivery_id;
    update public.orders set status = 'delivered' where id = v_order_id;
  end if;
end;
$$;

revoke all on function public.driver_update_delivery_status(uuid, text, text) from public, anon;
grant execute on function public.driver_update_delivery_status(uuid, text, text) to authenticated;

-- Admin hanya mengurus konfirmasi dan kesiapan barang; driver mengurus perjalanan.
create or replace function public.admin_update_order_status(
  p_order_id uuid,
  p_new_status text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_current_status text;
  v_allowed boolean := false;
begin
  if not coalesce(public.is_admin(), false) then
    raise exception 'Hanya admin yang dapat mengubah status pesanan.';
  end if;
  if p_new_status not in ('confirmed','ready_for_pickup','cancelled') then
    raise exception 'Status pesanan tidak valid untuk admin.';
  end if;

  select o.status into v_current_status
  from public.orders o where o.id = p_order_id for update;

  if not found then
    raise exception 'Pesanan tidak ditemukan.';
  end if;

  v_allowed :=
    (v_current_status = 'pending' and p_new_status in ('confirmed','cancelled'))
    or (v_current_status = 'confirmed' and p_new_status in ('ready_for_pickup','cancelled'));

  if not v_allowed then
    raise exception 'Perubahan status dari % ke % tidak diizinkan.', v_current_status, p_new_status;
  end if;

  update public.orders set status = p_new_status where id = p_order_id;
end;
$$;

revoke all on function public.admin_update_order_status(uuid, text) from public, anon;
grant execute on function public.admin_update_order_status(uuid, text) to authenticated;
