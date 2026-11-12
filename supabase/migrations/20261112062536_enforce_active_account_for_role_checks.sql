-- Every role-based authorization check must reject suspended accounts.
-- This also protects SECURITY DEFINER RPCs that rely on is_admin/current_user_has_role.
create or replace function public.current_user_has_role(required_role text)
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
      and p.role = required_role
      and p.account_status = 'active'
  );
$function$;
