-- Restrict trigger-only helpers from direct RPC execution.
revoke execute on function public.handle_new_user() from public;
revoke execute on function public.record_order_status_history() from public;
revoke execute on function public.record_seller_commission_on_delivery() from public;
revoke execute on function public.set_updated_at() from public;

-- is_admin is useful to signed-in clients, but not anonymous callers.
revoke execute on function public.is_admin() from anon;

-- set_updated_at only uses pg_catalog built-ins and trigger records.
alter function public.set_updated_at() set search_path = pg_catalog;
