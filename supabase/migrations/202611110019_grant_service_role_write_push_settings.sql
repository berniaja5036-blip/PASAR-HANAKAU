-- Allow the Edge Function service role to persist the public VAPID key.
-- Browser users retain read-only access through the existing authenticated policy.
grant select, insert, update on table public.push_settings to service_role;
