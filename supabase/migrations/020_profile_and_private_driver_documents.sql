-- Pasar Hanakau: profil lengkap, status WhatsApp, dan dokumen privat driver.
-- Jalankan sekali di Supabase SQL Editor setelah migrasi 019.

alter table public.profiles
  add column if not exists full_address text not null default '',
  add column if not exists whatsapp_verified_at timestamptz;

alter table public.driver_applications
  add column if not exists whatsapp_number text,
  add column if not exists ktp_image_path text,
  add column if not exists face_image_path text;

-- Metadata pendaftaran disimpan saat trigger membuat profil baru.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $ph$
begin
  insert into public.profiles (id, full_name, phone, full_address)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    nullif(new.raw_user_meta_data ->> 'phone', ''),
    coalesce(new.raw_user_meta_data ->> 'full_address', '')
  );
  insert into public.role_memberships (user_id, role, status)
  values (new.id, 'buyer', 'approved')
  on conflict (user_id, role) do nothing;
  return new;
end;
$ph$;

-- Dokumen identitas disimpan privat, bukan pada bucket publik.
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
  'Alamat lengkap pengguna.';
comment on column public.profiles.whatsapp_verified_at is
  'Hanya diisi oleh verifikasi OTP tepercaya; tetap NULL sebelum integrasi resmi.';
comment on column public.driver_applications.ktp_image_path is
  'Path KTP di bucket privat driver-private-documents.';
comment on column public.driver_applications.face_image_path is
  'Path foto wajah di bucket privat driver-private-documents.';
