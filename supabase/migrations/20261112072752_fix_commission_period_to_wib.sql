-- Commission periods follow the marketplace's local business timezone (WIB).
create or replace function public.record_seller_commission_on_delivery()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_rate numeric(5,2);
begin
  if new.status = 'delivered' and old.status is distinct from new.status then
    select rate_percent into v_rate
      from public.seller_commission_settings where id = true;

    insert into public.seller_commission_entries
      (order_id,seller_id,shop_id,period_start,basis_amount,rate_percent,commission_amount)
    select
      new.id,
      s.owner_id,
      oi.shop_id,
      (pg_catalog.date_trunc('month', pg_catalog.now() at time zone 'Asia/Jakarta'))::date,
      sum(oi.line_total),
      coalesce(v_rate,2.00),
      round(sum(oi.line_total) * coalesce(v_rate,2.00) / 100.0,0)
    from public.order_items oi
    join public.shops s on s.id = oi.shop_id
    where oi.order_id = new.id
    group by s.owner_id,oi.shop_id
    on conflict (order_id) do nothing;
  end if;
  return new;
end;
$function$;
