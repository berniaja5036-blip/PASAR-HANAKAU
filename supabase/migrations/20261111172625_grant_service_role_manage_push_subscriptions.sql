-- Allow the push notification Edge Function to manage device subscriptions.
-- Authenticated users remain restricted by the existing own-row RLS policies.
grant select, insert, update, delete on table public.push_subscriptions to service_role;
