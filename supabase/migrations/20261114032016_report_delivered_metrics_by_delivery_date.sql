create or replace function public.admin_get_marketplace_statistics(
  p_from timestamp with time zone,
  p_to timestamp with time zone
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_result jsonb;
begin
  if not coalesce(public.is_admin(), false) then
    raise exception 'Hanya admin yang dapat melihat statistik marketplace.';
  end if;

  if p_from is null or p_to is null or p_to <= p_from
     or p_to - p_from > interval '366 days' then
    raise exception 'Rentang laporan tidak valid (maksimal 366 hari).';
  end if;

  with delivered_orders as (
    select distinct on (h.order_id)
      h.order_id,
      h.changed_at as delivered_at
    from public.order_status_history h
    where h.to_status = 'delivered'
    order by h.order_id, h.changed_at asc, h.id asc
  ),
  order_daily as (
    select
      (date_trunc('day', o.created_at at time zone 'Asia/Jakarta'))::date as day,
      count(*) as orders
    from public.orders o
    where o.created_at >= p_from and o.created_at < p_to
    group by 1
  ),
  delivered_daily as (
    select
      (date_trunc('day', d.delivered_at at time zone 'Asia/Jakarta'))::date as day,
      count(*) as delivered,
      coalesce(sum(o.subtotal - o.discount_amount), 0) as sales
    from delivered_orders d
    join public.orders o on o.id = d.order_id
    where d.delivered_at >= p_from and d.delivered_at < p_to
      and o.status = 'delivered'
    group by 1
  )
  select jsonb_build_object(
    'from', p_from,
    'to', p_to,
    'orders_total', (
      select count(*) from public.orders o
      where o.created_at >= p_from and o.created_at < p_to
    ),
    'orders_delivered', (
      select count(*) from delivered_orders d
      join public.orders o on o.id = d.order_id
      where d.delivered_at >= p_from and d.delivered_at < p_to
        and o.status = 'delivered'
    ),
    'orders_open', (
      select count(*) from public.orders o
      where o.created_at >= p_from and o.created_at < p_to
        and o.status in ('pending','confirmed','ready_for_pickup','picked_up')
    ),
    'orders_cancelled', (
      select count(*) from public.orders o
      where o.created_at >= p_from and o.created_at < p_to
        and o.status = 'cancelled'
    ),
    'sales_delivered', (
      select coalesce(sum(o.subtotal - o.discount_amount), 0)
      from delivered_orders d
      join public.orders o on o.id = d.order_id
      where d.delivered_at >= p_from and d.delivered_at < p_to
        and o.status = 'delivered'
    ),
    'discounts_delivered', (
      select coalesce(sum(o.discount_amount), 0)
      from delivered_orders d
      join public.orders o on o.id = d.order_id
      where d.delivered_at >= p_from and d.delivered_at < p_to
        and o.status = 'delivered'
    ),
    'delivery_fees_delivered', (
      select coalesce(sum(o.delivery_fee), 0)
      from delivered_orders d
      join public.orders o on o.id = d.order_id
      where d.delivered_at >= p_from and d.delivered_at < p_to
        and o.status = 'delivered'
    ),
    'commission_earned', (
      select coalesce(sum(e.commission_amount), 0)
      from public.seller_commission_entries e
      where e.created_at >= p_from and e.created_at < p_to
    ),
    'commission_paid', (
      select coalesce(sum(i.commission_amount), 0)
      from public.seller_commission_invoices i
      where i.status = 'paid'
        and i.reviewed_at >= p_from and i.reviewed_at < p_to
    ),
    'buyers_total', (select count(*) from public.profiles p where p.role = 'buyer'),
    'sellers_total', (select count(*) from public.profiles p where p.role = 'seller'),
    'drivers_total', (select count(*) from public.profiles p where p.role = 'driver'),
    'shops_approved', (select count(*) from public.shops s where s.status = 'approved'),
    'products_active', (select count(*) from public.products p where p.status = 'active'),
    'daily', (
      select coalesce(
        jsonb_agg(
          jsonb_build_object(
            'day', coalesce(o.day, d.day),
            'orders', coalesce(o.orders, 0),
            'delivered', coalesce(d.delivered, 0),
            'sales', coalesce(d.sales, 0)
          ) order by coalesce(o.day, d.day)
        ),
        '[]'::jsonb
      )
      from order_daily o
      full outer join delivered_daily d on d.day = o.day
    )
  ) into v_result;

  return v_result;
end;
$function$;

revoke all on function public.admin_get_marketplace_statistics(timestamptz,timestamptz)
  from public, anon;
grant execute on function public.admin_get_marketplace_statistics(timestamptz,timestamptz)
  to authenticated;
