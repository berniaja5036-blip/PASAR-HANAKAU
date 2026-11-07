-- Pasar Hanakau: unggah foto produk melalui Supabase Storage.
-- Jalankan sekali setelah migrasi 001-006.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('product-images', 'product-images', true, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists product_images_public_read on storage.objects;
create policy product_images_public_read
on storage.objects for select
to public
using (bucket_id = 'product-images');

drop policy if exists product_images_seller_upload on storage.objects;
create policy product_images_seller_upload
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'product-images'
  and (
    exists (
      select 1 from public.shops s
      where s.id::text = (storage.foldername(name))[1]
        and s.owner_id = (select auth.uid())
        and s.status = 'approved'
        and (select public.current_user_has_role('seller'))
    )
    or (select public.is_admin())
  )
);

drop policy if exists product_images_seller_update on storage.objects;
create policy product_images_seller_update
on storage.objects for update
to authenticated
using (
  bucket_id = 'product-images'
  and (
    exists (
      select 1 from public.shops s
      where s.id::text = (storage.foldername(name))[1]
        and s.owner_id = (select auth.uid())
        and (select public.current_user_has_role('seller'))
    )
    or (select public.is_admin())
  )
)
with check (
  bucket_id = 'product-images'
  and (
    exists (
      select 1 from public.shops s
      where s.id::text = (storage.foldername(name))[1]
        and s.owner_id = (select auth.uid())
        and (select public.current_user_has_role('seller'))
    )
    or (select public.is_admin())
  )
);

drop policy if exists product_images_seller_delete on storage.objects;
create policy product_images_seller_delete
on storage.objects for delete
to authenticated
using (
  bucket_id = 'product-images'
  and (
    exists (
      select 1 from public.shops s
      where s.id::text = (storage.foldername(name))[1]
        and s.owner_id = (select auth.uid())
        and (select public.current_user_has_role('seller'))
    )
    or (select public.is_admin())
  )
);
