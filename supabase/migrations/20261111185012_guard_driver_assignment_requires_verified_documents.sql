-- Prevent assignment to legacy approved driver profiles with missing identity files.
-- Existing records and assignments are intentionally left unchanged.
create or replace function public.admin_assign_delivery(p_order_id uuid, p_driver_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_order_status text;
  v_delivery_status text;
begin
  if not coalesce(public.is_admin(), false) then
    raise exception 'Hanya admin yang dapat menugaskan driver.';
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
      and nullif(pg_catalog.trim(da.ktp_image_path), '') is not null
      and nullif(pg_catalog.trim(da.face_image_path), '') is not null
  ) then
    raise exception 'Dokumen identitas driver belum lengkap. Lengkapi dan verifikasi foto KTP serta foto wajah sebelum menerima tugas.';
  end if;

  select status into v_order_status
  from public.orders
  where id = p_order_id
  for update;

  if not found then
    raise exception 'Pesanan tidak ditemukan.';
  end if;
  if v_order_status <> 'ready_for_pickup' then
    raise exception 'Pesanan harus berstatus Siap dijemput sebelum ditugaskan.';
  end if;

  select status into v_delivery_status
  from public.deliveries
  where order_id = p_order_id
  for update;

  if not found then
    raise exception 'Data pengiriman untuk pesanan ini tidak ditemukan.';
  end if;
  if v_delivery_status not in ('waiting','assigned') then
    raise exception 'Pengiriman sudah berjalan dan tidak dapat ditugaskan ulang.';
  end if;

  if exists (
    select 1
    from public.deliveries d
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
