-- Public registrations must start as buyer accounts.
-- Seller and driver access is granted only after their application is approved.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  insert into public.profiles (id, full_name, phone, full_address, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    nullif(new.raw_user_meta_data ->> 'phone', ''),
    coalesce(new.raw_user_meta_data ->> 'full_address', ''),
    'buyer'
  )
  on conflict (id) do nothing;

  return new;
end;
$function$;
