create table if not exists public.buyer_wishlist (
  id uuid primary key default gen_random_uuid(),
  buyer_id uuid not null references auth.users(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (buyer_id, product_id)
);
create index if not exists buyer_wishlist_buyer_created_idx on public.buyer_wishlist(buyer_id, created_at desc);
alter table public.buyer_wishlist enable row level security;
grant select, insert, delete on public.buyer_wishlist to authenticated;
create policy buyer_wishlist_owner_read on public.buyer_wishlist for select to authenticated
using (buyer_id = (select auth.uid()));
create policy buyer_wishlist_owner_add_active_product on public.buyer_wishlist for insert to authenticated
with check (
  buyer_id = (select auth.uid())
  and exists (select 1 from public.products p where p.id = product_id and p.status = 'active')
);
create policy buyer_wishlist_owner_delete on public.buyer_wishlist for delete to authenticated
using (buyer_id = (select auth.uid()));