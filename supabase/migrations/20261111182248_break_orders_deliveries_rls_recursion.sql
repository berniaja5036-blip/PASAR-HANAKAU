create or replace function public.current_user_is_assigned_driver(p_order_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1
    from public.deliveries d
    where d.order_id = p_order_id
      and d.driver_id = (select auth.uid())
  );
$function$;

create or replace function public.current_user_can_read_delivery_order(p_order_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1
    from public.orders o
    where o.id = p_order_id
      and (
        o.buyer_id = (select auth.uid())
        or exists (
          select 1
          from public.order_items oi
          join public.shops s on s.id = oi.shop_id
          where oi.order_id = o.id
            and s.owner_id = (select auth.uid())
        )
      )
  );
$function$;

revoke all on function public.current_user_is_assigned_driver(uuid) from public, anon;
revoke all on function public.current_user_can_read_delivery_order(uuid) from public, anon;
grant execute on function public.current_user_is_assigned_driver(uuid) to authenticated;
grant execute on function public.current_user_can_read_delivery_order(uuid) to authenticated;

drop policy if exists orders_assigned_driver_read on public.orders;
create policy orders_assigned_driver_read
on public.orders
for select
to authenticated
using (public.current_user_is_assigned_driver(id));

drop policy if exists deliveries_buyer_seller_assigned_read on public.deliveries;
create policy deliveries_buyer_seller_assigned_read
on public.deliveries
for select
to authenticated
using (
  driver_id is not null
  and public.current_user_can_read_delivery_order(order_id)
);
