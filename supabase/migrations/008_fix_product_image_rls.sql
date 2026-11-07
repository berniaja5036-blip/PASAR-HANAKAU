-- Pasar Hanakau: perbaikan RLS unggah foto produk.
-- Fungsi SECURITY DEFINER memeriksa toko tanpa terkena RLS tabel shops.
create or replace function public.can_upload_product_image(shop_folder text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.shops s
    join public.profiles p on p.id = s.owner_id
    where s.id::text = shop_folder
      and s.owner_id = (select auth.uid())
      and s.status = 'approved'
      and p.role = 'seller'
  );
$$;

revoke all on function public.can_upload_product_image(text) from public;
grant execute on function public.can_upload_product_image(text) to authenticated;

drop policy if exists product_images_seller_upload on storage.objects;
create policy product_images_seller_upload
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'product-images'
  and (
    (select public.can_upload_product_image((storage.foldername(name))[1]))
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
    (select public.can_upload_product_image((storage.foldername(name))[1]))
    or (select public.is_admin())
  )
)
with check (
  bucket_id = 'product-images'
  and (
    (select public.can_upload_product_image((storage.foldername(name))[1]))
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
    (select public.can_upload_product_image((storage.foldername(name))[1]))
    or (select public.is_admin())
  )
);
