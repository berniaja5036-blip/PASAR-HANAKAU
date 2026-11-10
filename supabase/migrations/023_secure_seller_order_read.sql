-- Pasar Hanakau: batasi data pesanan yang dapat dibaca langsung oleh penjual.
-- Penjual hanya menerima nomor/status pesanan, catatan, item dari tokonya,
-- dan riwayat status. Alamat serta koordinat pengantaran pembeli tidak dikembalikan.
-- Jalankan sekali setelah migrasi 022.

create or replace function public.seller_list_orders()
returns table (
  id uuid,
  order_number text,
  status text,
  created_at timestamptz,
  notes text,
  order_items jsonb,
  order_status_history jsonb
)
language sql
stable
security definer
set search_path = ''
as $function$
  select
    o.id,
    o.order_number,
    o.status,
    o.created_at,
    o.notes,
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'product_name', oi.product_name,
          'quantity', oi.quantity,
          'unit_price', oi.unit_price,
          'line_total', oi.line_total
        )
        order by oi.created_at, oi.id
      )
      from public.order_items as oi
      join public.shops as s on s.id = oi.shop_id
      where oi.order_id = o.id
        and s.owner_id = (select auth.uid())
    ), '[]'::jsonb) as order_items,
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'from_status', h.from_status,
          'to_status', h.to_status,
          'changed_at', h.changed_at
        )
        order by h.changed_at, h.id
      )
      from public.order_status_history as h
      where h.order_id = o.id
    ), '[]'::jsonb) as order_status_history
  from public.orders as o
  where (select public.current_user_has_role('seller'))
    and exists (
      select 1
      from public.order_items as oi
      join public.shops as s on s.id = oi.shop_id
      where oi.order_id = o.id
        and s.owner_id = (select auth.uid())
    )
  order by o.created_at desc
  limit 50;
$function$;

revoke all on function public.seller_list_orders() from public, anon;
grant execute on function public.seller_list_orders() to authenticated;

-- Setelah UI memakai RPC terbatas, penjual tidak lagi boleh membaca baris
-- orders secara langsung karena RLS tingkat baris tidak menyaring kolom sensitif.
drop policy if exists orders_seller_own_shop_read on public.orders;

comment on function public.seller_list_orders() is
  'Returns seller-owned order data without buyer delivery address or GPS coordinates.';
