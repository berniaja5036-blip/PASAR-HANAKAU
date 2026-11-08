-- Pasar Hanakau: perbaiki pembuatan akun setelah migrasi 020.
-- Skema aplikasi ini menggunakan profiles.role (default buyer), bukan role_memberships.
-- Trigger lama dari migrasi 020 mencoba menulis ke role_memberships yang tidak ada,
-- sehingga Supabase menolak pendaftaran akun baru.

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $ph$
begin
  insert into public.profiles (id, full_name, phone, full_address)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    nullif(new.raw_user_meta_data ->> 'phone', ''),
    coalesce(new.raw_user_meta_data ->> 'full_address', '')
  )
  on conflict (id) do nothing;

  return new;
end;
$ph$;

-- Pastikan trigger pembuatan profil terpasang tepat satu kali.
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();
