-- Add indexes for foreign-key columns used in joins and deletes/updates.
create index if not exists delivery_fee_settings_updated_by_idx on public.delivery_fee_settings(updated_by);
create index if not exists driver_applications_reviewed_by_idx on public.driver_applications(reviewed_by);
create index if not exists order_cancellation_requests_reviewed_by_idx on public.order_cancellation_requests(reviewed_by);
create index if not exists order_items_product_id_idx on public.order_items(product_id);
create index if not exists order_status_history_changed_by_idx on public.order_status_history(changed_by);
create index if not exists seller_applications_reviewed_by_idx on public.seller_applications(reviewed_by);
create index if not exists seller_commission_entries_invoice_id_idx on public.seller_commission_entries(invoice_id);
create index if not exists seller_commission_entries_shop_id_idx on public.seller_commission_entries(shop_id);
create index if not exists seller_commission_invoices_reviewed_by_idx on public.seller_commission_invoices(reviewed_by);
create index if not exists seller_commission_settings_updated_by_idx on public.seller_commission_settings(updated_by);
