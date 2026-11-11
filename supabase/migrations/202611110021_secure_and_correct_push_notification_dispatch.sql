-- Move the existing webhook bearer token into Supabase Vault and point
-- notification inserts at the push-notifications Edge Function.
do $$
declare
  v_token text;
begin
  select (regexp_match(pg_get_triggerdef(t.oid), 'Bearer ([^"]+)'))[1]
    into v_token
  from pg_trigger t
  join pg_class c on c.oid=t.tgrelid
  join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public'
    and c.relname='notifications'
    and t.tgname='pasar-hanakau-push'
    and not t.tgisinternal;

  if v_token is null or length(v_token) < 40 then
    raise exception 'Existing push webhook authorization token could not be safely migrated';
  end if;

  if not exists (select 1 from vault.decrypted_secrets where name='pasar_hanakau_push_webhook_token') then
    perform vault.create_secret(v_token, 'pasar_hanakau_push_webhook_token', 'Authorization token for the Pasar Hanakau push notification database trigger');
  end if;
end $$;

drop trigger if exists "pasar-hanakau-push" on public.notifications;

create or replace function public.dispatch_pasar_hanakau_push()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_token text;
begin
  select decrypted_secret into v_token
  from vault.decrypted_secrets
  where name='pasar_hanakau_push_webhook_token'
  limit 1;

  if v_token is null then
    raise warning 'Pasar Hanakau push webhook token is not available in Vault';
    return new;
  end if;

  perform net.http_post(
    url := 'https://wnnnhiocyyozlkfqupav.supabase.co/functions/v1/push-notifications',
    body := jsonb_build_object(
      'record', to_jsonb(new),
      'type', 'INSERT',
      'table', 'notifications',
      'schema', 'public'
    ),
    params := '{}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_token
    ),
    timeout_milliseconds := 5000
  );

  return new;
end;
$$;

revoke all on function public.dispatch_pasar_hanakau_push() from public, anon, authenticated;
create trigger "pasar-hanakau-push"
after insert on public.notifications
for each row execute function public.dispatch_pasar_hanakau_push();
