do $$
declare
  r record;
begin
  for r in
    select schemaname, tablename
    from pg_tables
    where schemaname = 'public'
  loop
    execute format('revoke truncate, trigger, references on table %I.%I from anon, authenticated', r.schemaname, r.tablename);
    execute format('revoke delete on table %I.%I from anon', r.schemaname, r.tablename);
  end loop;
end
$$;

revoke delete on table
  public.deliveries,
  public.driver_profiles,
  public.order_items,
  public.orders,
  public.shops
from authenticated;
