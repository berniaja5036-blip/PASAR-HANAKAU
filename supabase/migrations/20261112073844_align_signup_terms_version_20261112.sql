-- Keep new-signup consent aligned with the legal pages updated on 2026-11-12.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_terms_accepted_at text;
  v_terms_version text;
begin
  v_terms_accepted_at := nullif(new.raw_user_meta_data ->> 'accepted_terms_at', '');
  v_terms_version := coalesce(new.raw_user_meta_data ->> 'accepted_terms_version', '');

  if v_terms_accepted_at is null or v_terms_version <> '2026-11-12' then
    raise exception 'Pendaftaran memerlukan persetujuan Syarat dan Ketentuan serta Kebijakan Privasi versi 2026-11-12.';
  end if;

  -- Role selection from user-editable metadata is only a UI request.
  -- Every new account starts as buyer; admin approval grants seller/driver.
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
