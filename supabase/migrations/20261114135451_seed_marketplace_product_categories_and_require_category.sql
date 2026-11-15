insert into public.categories (name,is_active) values ('Makanan','true'),('Minuman','true'),('Sayur & Bumbu','true'),('Buah-buahan','true'),('Kebutuhan Rumah Tangga','true'),('Perlengkapan Dapur','true'),('Fashion & Aksesori','true'),('Elektronik','true'),('Kesehatan & Kecantikan','true'),('Perlengkapan Bayi & Anak','true'),('Alat Tulis & Sekolah','true'),('Pertanian & Peternakan','true'),('Lainnya','true') on conflict do nothing;
update public.products set category_id=(select id from public.categories where name='Lainnya' and is_active=true order by created_at limit 1) where category_id is null;
alter table public.products alter column category_id set not null;
create index if not exists products_category_status_stock_idx on public.products(category_id,status,stock);
