-- Pasar Hanakau: profil lengkap, status verifikasi WhatsApp, dan dokumen privat driver.
-- Jalankan sekali di Supabase SQL Editor setelah migrasi 019.
-- Status verifikasi tetap false sampai OTP sungguhan divalidasi oleh penyedia resmi.

alter table public.profiles
  add column if not exists full_address text not null default '',
  add column if not exists whatsapp_verified_at timestamptz;

alter table public.driver_applications
  add column if not exists whatsapp_number text,
  add column if not exists ktp_image_path text,
  add column if not exists face_image_path text;

-- Dokumen identitas tidak boleh berada di bucket publik.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'driver-private-documents',
  'driver-private-documents',
  false,
  5242880,
  array['image/jpeg','image/png','image/webp']
)
on conflict (id) do update
set public = false,
    file_size_limit = 5242880,
    allowed_mime_types = array['image/jpeg','image/png','image/webp'];

drop policy if exists driver_docs_owner_upload on storage.objects;
create policy driver_docs_owner_upload
on storage.objects for insert to authenticated
with check (
  bucket_id = 'driver-private-documents'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists driver_docs_owner_read_or_admin on storage.objects;
create policy driver_docs_owner_read_or_admin
on storage.objects for select to authenticated
using (
  bucket_id = 'driver-private-documents'
  and (
    (storage.foldername(name))[1] = (select auth.uid())::text
    or (select public.is_admin())
  )
);

drop policy if exists driver_docs_owner_delete on storage.objects;
create policy driver_docs_owner_delete
on storage.objects for delete to authenticated
using (
  bucket_id = 'driver-private-documents'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

comment on column public.profiles.full_address is
  'Alamat lengkap profil pengguna; pemilik dan admin dapat melihat sesuai kebijakan RLS profiles.';
comment on column public.profiles.whatsapp_verified_at is
  'Diisi hanya oleh alur verifikasi OTP tepercaya setelah penyedia WhatsApp mengonfirmasi kode.';
comment on column public.driver_applications.ktp_image_path is
  'Path dokumen KTP di bucket privat driver-private-documents; bukan URL publik.';
comment on column public.driver_applications.face_image_path is
  'Path foto wajah di bucket privat driver-private-documents; bukan URL publik.';
