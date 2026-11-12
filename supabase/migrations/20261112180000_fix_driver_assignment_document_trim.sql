-- Use PostgreSQL's built-in btrim function in the driver document guard.
-- pg_catalog.trim(text) is not a callable function and would fail at assignment time.
create or replace function public.admin_assign_delivery(p_order_id uuid, p_driver_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_order_status text;
  v_delivery_status text;
begin
  if not coalesce(public.is_admin(), false) then
    raise exception 'Hanya admin yang dapat menugaskan driver.';
  end if;

  perform 1
  from public.profiles p
  where p.id = p_driver_id
    and p.role = 'driver'
    and p.account_status = 'active'
  for update;

  if not found then
    raise exception 'Akun driver tidak aktif atau tidak ditemukan.';
  end if;

  perform 1
  from public.driver_profiles dp
  where dp.id = p_driver_id
    and dp.approval_status = 'approved'
  for update;

  if not found then
    raise exception 'Akun driver belum disetujui atau tidak ditemukan.';
  end if;

  if not exists (
    select 1
    from public.driver_applications da
    where da.user_id = p_driver_id
      and da.status = 'approved'
      and nullif(pg_catalog.btrim(da.ktp_image_path), '') is not null
      and nullif(pg_catalog.btrim(da.face_image_path), '') is not null
      and exists (
        select 1 from storage.objects so
        where so.bucket_id = 'driver-private-documents'
          and so.name = da.ktp_image_path
          and (storage.foldername(so.name))[1] = da.user_id::text
      )
      and exists (
        select 1 from storage.objects so
        where so.bucket_id = 'driver-private-documents'
          and so.name = da.face_image_path
          and (storage.foldername(so.name))[1] = da.user_id::text
      )
  ) then
    raise exception 'Dokumen identitas driver belum lengkap atau berkasnya tidak ditemukan. Lengkapi dan verifikasi foto KTP serta foto wajah sebelum menerima tugas.';
  end if;

  select status into v_order_status
  from public.orders
  where id = p_order_id
  for update;

  if not found then raise exception 'Pesanan tidak ditemukan.'; end if;
  if v_order_status <> 'ready_for_pickup' then
    raise exception 'Pesanan harus berstatus Siap dijemput sebelum ditugaskan.';
  end if;

  select status into v_delivery_status
  from public.deliveries
  where order_id = p_order_id
  for update;

  if not found then raise exception 'Data pengiriman untuk pesanan ini tidak ditemukan.'; end if;
  if v_delivery_status not in ('waiting','assigned') then
    raise exception 'Pengiriman sudah berjalan dan tidak dapat ditugaskan ulang.';
  end if;

  if exists (
    select 1 from public.deliveries d
    where d.driver_id = p_driver_id
      and d.order_id <> p_order_id
      and d.status in ('assigned','picked_up')
  ) then
    raise exception 'Driver sedang bertugas pada pesanan lain. Pilih driver yang standby.';
  end if;

  update public.deliveries
     set driver_id = p_driver_id,
         status = 'assigned',
         assigned_at = pg_catalog.now()
   where order_id = p_order_id;
end;
$function$;
