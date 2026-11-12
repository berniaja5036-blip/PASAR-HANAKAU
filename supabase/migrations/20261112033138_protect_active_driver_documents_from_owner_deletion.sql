-- Keep identity documents available while a driver application is pending or approved.
-- Owners may still clean up orphaned uploads and documents from rejected applications.
drop policy if exists driver_docs_owner_delete on storage.objects;
create policy driver_docs_owner_delete
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'driver-private-documents'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and not exists (
    select 1
    from public.driver_applications da
    where da.user_id = (select auth.uid())
      and da.status in ('pending','approved')
      and name in (da.ktp_image_path, da.face_image_path)
  )
);
