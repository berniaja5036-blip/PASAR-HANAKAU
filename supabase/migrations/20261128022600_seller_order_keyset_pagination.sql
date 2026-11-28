begin;

-- Add keyset pagination without changing the legacy seller_list_orders() RPC.
-- The result deliberately excludes buyer delivery address and GPS coordinates.
create or replace function public.seller_list_orders_page(
  p_before_created_at timestamptz default null,
  p_before_id uuid default null,
  p_page_size integer default 50
)
returns table (
  id uuid,
  order_number text,
  status text,
  created_at timestamptz,
  notes text,
  order_items jsonb,
  order_status_history jsonb,
  has_more boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := (select auth.uid());
begin
  if v_user_id is null then
    raise exception 'Silakan masuk terlebih dahulu.';
  end if;

  if not coalesce((select public.current_user_has_role('seller')), false) then
    raise exception 'Akun penjual aktif diperlukan.';
  end if;

  if p_page_size is null or p_page_size < 1 or p_page_size > 50 then
    raise exception 'Ukuran halaman pesanan harus antara 1 dan 50.';
  end if;

  if (p_before_created_at is null) <> (p_before_id is null) then
    raise exception 'Kursor halaman pesanan tidak lengkap.';
  end if;

  return query
  with candidates as materialized (
    select
      o.id,
      o.order_number,
      o.status,
      o.created_at,
      o.notes
    from public.orders as o
    where exists (
      select 1
      from public.order_items as oi
      join public.shops as s on s.id = oi.shop_id
      where oi.order_id = o.id
        and s.owner_id = v_user_id
    )
      and (
        p_before_created_at is null
        or (o.created_at, o.id) < (p_before_created_at, p_before_id)
      )
    order by o.created_at desc, o.id desc
    limit (p_page_size + 1)
  ),
  page as (
    select c.*
    from candidates as c
    order by c.created_at desc, c.id desc
    limit p_page_size
  ),
  page_meta as (
    select count(*) > p_page_size as has_more
    from candidates
  )
  select
    p.id,
    p.order_number,
    p.status,
    p.created_at,
    p.notes,
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
      where oi.order_id = p.id
        and s.owner_id = v_user_id
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
      where h.order_id = p.id
    ), '[]'::jsonb) as order_status_history,
    page_meta.has_more
  from page as p
  cross join page_meta
  order by p.created_at desc, p.id desc;
end;
$function$;

revoke all on function public.seller_list_orders_page(timestamptz, uuid, integer) from public, anon;
grant execute on function public.seller_list_orders_page(timestamptz, uuid, integer) to authenticated;

comment on function public.seller_list_orders_page(timestamptz, uuid, integer) is
  'Keyset-paginated seller order history. Returns only the seller own order items and never buyer delivery address or GPS coordinates.';

commit;
