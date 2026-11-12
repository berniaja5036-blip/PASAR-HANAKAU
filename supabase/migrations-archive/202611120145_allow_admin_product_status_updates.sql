-- Allow authenticated admins to publish or unpublish products through the admin panel.
-- Sellers receive this column-level privilege at the SQL layer too, but the
-- products_approval_status_guard trigger rejects every status change unless
-- public.is_admin() is true. Existing RLS policies continue to scope row access.
GRANT UPDATE (status) ON TABLE public.products TO authenticated;
