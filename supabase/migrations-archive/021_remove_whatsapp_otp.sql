-- Pasar Hanakau: hapus seluruh ketergantungan pada OTP WhatsApp.
-- Aman dijalankan bila migrasi 020 versi lama sudah pernah diterapkan.

drop trigger if exists profiles_phone_change_clears_verification on public.profiles;
drop function if exists public.clear_whatsapp_verification_on_phone_change();
alter table public.profiles drop column if exists whatsapp_verified_at;

create or replace function public.approve_seller_application(application_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $ph$
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
  if application_row.pickup_latitude is null or application_row.pickup_longitude is null then
    raise exception 'Titik penjemputan toko belum dipilih pada peta.';
  end if;

  update public.profiles set role = 'seller'
  where id = application_row.user_id;

  insert into public.shops
    (owner_id, name, description, address, status, pickup_latitude, pickup_longitude)
  values
    (application_row.user_id, application_row.shop_name,
     application_row.shop_description, application_row.shop_address, 'approved',
     application_row.pickup_latitude, application_row.pickup_longitude)
  returning id into new_shop_id;

  update public.seller_applications
  set status = 'approved', reviewed_by = auth.uid(), reviewed_at = now()
  where id = application_row.id;

  return new_shop_id;
end;
$ph$;
revoke all on function public.approve_seller_application(uuid) from public, anon;
grant execute on function public.approve_seller_application(uuid) to authenticated;

create or replace function public.admin_review_driver_application(
  p_application_id uuid,
  p_approve boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $ph$
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

  if not found then raise exception 'Pendaftaran driver tidak ditemukan.'; end if;
  if v_app.status <> 'pending' then raise exception 'Pendaftaran driver ini sudah diproses.'; end if;

  if p_approve then
    if v_app.ktp_image_path is null or v_app.face_image_path is null then
      raise exception 'Foto KTP dan foto wajah wajib tersedia sebelum persetujuan.';
    end if;
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
$ph$;
revoke all on function public.admin_review_driver_application(uuid, boolean) from public, anon;
grant execute on function public.admin_review_driver_application(uuid, boolean) to authenticated;
