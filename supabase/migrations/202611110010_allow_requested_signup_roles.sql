-- Allow public registration to request buyer, seller, or driver access.
-- Admin role can never be self-assigned through user metadata.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $ph$
declare
  v_requested_role text;
  v_safe_role text;
begin
  v_requested_role := coalesce(new.raw_user_meta_data ->> 'requested_role', 'buyer');
  v_safe_role := case
    when v_requested_role in ('seller', 'driver') then v_requested_role
    else 'buyer'
  end;

  insert into public.profiles (id, full_name, phone, full_address, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    nullif(new.raw_user_meta_data ->> 'phone', ''),
    coalesce(new.raw_user_meta_data ->> 'full_address', ''),
    v_safe_role
  )
  on conflict (id) do nothing;

  return new;
end;
$ph$;
