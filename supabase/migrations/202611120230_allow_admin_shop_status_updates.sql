-- Permit the authenticated admin session to update shop approval status.
-- The existing shops_approval_status_guard trigger rejects status changes
-- unless public.is_admin() is true; RLS continues to scope shop rows.
GRANT UPDATE (status) ON TABLE public.shops TO authenticated;
