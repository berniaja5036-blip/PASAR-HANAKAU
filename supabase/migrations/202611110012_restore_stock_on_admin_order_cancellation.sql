-- Restore reserved product stock when an administrator directly cancels an order.
-- This keeps stock restoration atomic with the order status transition.
create or replace function public.admin_update_order_status(p_order_id uuid, p_new_status text)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_current_status text;
  v_allowed boolean := false;
begin
  if not coalesce(public.is_admin(), false) then
    raise exception 'Hanya admin yang dapat mengubah status pesanan.';
  end if;

  if p_new_status not in ('confirmed', 'ready_for_pickup', 'cancelled') then
    raise exception 'Status pesanan tidak valid untuk admin.';
  end if;

  select o.status into v_current_status
  from public.orders o
  where o.id = p_order_id
  for update;

  if not found then
    raise exception 'Pesanan tidak ditemukan.';
  end if;

  if v_current_status = 'pending'
     and p_new_status = 'confirmed'
     and exists (
       select 1 from public.order_cancellation_requests r
       where r.order_id = p_order_id and r.status = 'pending'
     ) then
    raise exception 'Pesanan memiliki permintaan pembatalan. Setujui atau tolak permintaan tersebut terlebih dahulu.';
  end if;

  v_allowed :=
    (v_current_status = 'pending' and p_new_status in ('confirmed', 'cancelled'))
    or (v_current_status = 'confirmed' and p_new_status in ('ready_for_pickup', 'cancelled'));

  if not v_allowed then
    raise exception 'Perubahan status dari % ke % tidak diizinkan.', v_current_status, p_new_status;
  end if;

  if p_new_status = 'cancelled' then
    -- Restore reserved stock exactly once, inside the same transaction as cancellation.
    update public.products p
       set stock = p.stock + item_totals.quantity
      from (
        select product_id, sum(quantity)::integer as quantity
          from public.order_items
         where order_id = p_order_id and product_id is not null
         group by product_id
      ) item_totals
     where p.id = item_totals.product_id;

    update public.deliveries
       set status = 'failed',
           delivery_notes = 'Pesanan dibatalkan oleh admin.'
     where order_id = p_order_id
       and status in ('waiting', 'assigned');
  end if;

  update public.orders
     set status = p_new_status
   where id = p_order_id;
end;
$function$;
