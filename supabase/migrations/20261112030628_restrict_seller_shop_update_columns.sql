-- Restrict seller updates to public shop details and pickup coordinates.
-- Sellers must not be able to approve their own shop or change ownership.
REVOKE UPDATE ON TABLE public.shops FROM authenticated;
GRANT UPDATE (name, address, description, pickup_latitude, pickup_longitude)
ON TABLE public.shops TO authenticated;
