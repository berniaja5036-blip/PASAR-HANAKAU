create or replace function public.current_user_is_active()
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1
    from public.profiles p
    where p.id = (select auth.uid())
      and p.account_status = 'active'
  );
$function$;

revoke all on function public.current_user_is_active() from public, anon;
grant execute on function public.current_user_is_active() to authenticated;

do $block$
declare
  t record;
begin
  for t in
    select c.relname
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind = 'r'
      and c.relrowsecurity
      and c.relname <> 'profiles'
  loop
    execute format('drop policy if exists active_account_required on public.%I', t.relname);
    execute format(
      'create policy active_account_required on public.%I as restrictive for all to authenticated using ((select public.current_user_is_active())) with check ((select public.current_user_is_active()))',
      t.relname
    );
  end loop;
end;
$block$;

drop policy if exists active_account_read_self on public.profiles;
create policy active_account_read_self on public.profiles
as restrictive for select to authenticated
using ((select public.current_user_is_active()) or id = (select auth.uid()));

drop policy if exists active_account_write on public.profiles;
create policy active_account_write on public.profiles
as restrictive for all to authenticated
using ((select public.current_user_is_active()))
with check ((select public.current_user_is_active()));