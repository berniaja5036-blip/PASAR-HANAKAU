-- The Edge Function validates the database webhook against a Vault secret.
-- Only service_role may retrieve it; browser roles have no execute permission.
create or replace function public.get_pasar_hanakau_push_webhook_token()
returns text
language sql
security definer
set search_path = pg_catalog
as $$
  select decrypted_secret
  from vault.decrypted_secrets
  where name='pasar_hanakau_push_webhook_token'
  limit 1
$$;

revoke all on function public.get_pasar_hanakau_push_webhook_token() from public, anon, authenticated;
grant execute on function public.get_pasar_hanakau_push_webhook_token() to service_role;
