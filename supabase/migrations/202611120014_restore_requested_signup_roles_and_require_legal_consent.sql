create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_requested_role text;
  v_safe_role text;
  v_terms_accepted_at text;
  v_terms_version text;
begin
  v_terms_accepted_at := nullif(new.raw_user_meta_data ->> 'accepted_terms_at', '');
  v_terms_version := coalesce(new.raw_user_meta_data ->> 'accepted_terms_version', '');

  if v_terms_accepted_at is null or v_terms_version <> '2026-11-11' then
    raise exception 'Pendaftaran memerlukan persetujuan Syarat dan Ketentuan serta Kebijakan Privasi versi 2026-11-11.';
  end if;

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
$function$;
