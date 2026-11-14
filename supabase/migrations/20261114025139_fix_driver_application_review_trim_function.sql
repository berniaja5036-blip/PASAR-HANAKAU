CREATE OR REPLACE FUNCTION public.admin_review_driver_application(p_application_id uuid, p_approve boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
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
    if nullif(pg_catalog.btrim(v_app.ktp_image_path), '') is null
       or nullif(pg_catalog.btrim(v_app.face_image_path), '') is null
       or not exists (
         select 1 from storage.objects so
         where so.bucket_id = 'driver-private-documents'
           and so.name = v_app.ktp_image_path
           and (storage.foldername(so.name))[1] = v_app.user_id::text
       )
       or not exists (
         select 1 from storage.objects so
         where so.bucket_id = 'driver-private-documents'
           and so.name = v_app.face_image_path
           and (storage.foldername(so.name))[1] = v_app.user_id::text
       ) then
      raise exception 'Foto KTP dan foto wajah yang benar-benar tersimpan wajib tersedia sebelum persetujuan.';
    end if;
    update public.profiles set role = 'driver' where id = v_app.user_id;
    insert into public.driver_profiles (id, vehicle_type, vehicle_plate, approval_status)
    values (v_app.user_id, v_app.vehicle_type, v_app.vehicle_plate, 'approved')
    on conflict (id) do update
      set vehicle_type = excluded.vehicle_type,
          vehicle_plate = excluded.vehicle_plate,
          approval_status = 'approved';
    update public.driver_applications
       set status = 'approved', reviewed_by = (select auth.uid()), reviewed_at = pg_catalog.now()
     where id = v_app.id;
  else
    update public.driver_applications
       set status = 'rejected', reviewed_by = (select auth.uid()), reviewed_at = pg_catalog.now()
     where id = v_app.id;
  end if;
end;
$function$;
