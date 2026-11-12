begin;
revoke all privileges on table public.profiles from anon, public, authenticated;
grant select on table public.profiles to authenticated;
grant update (full_name, full_address, phone) on table public.profiles to authenticated;

revoke all privileges on table public.user_public_profiles from anon, public, authenticated;
grant select on table public.user_public_profiles to authenticated;
grant insert (user_id, avatar_path) on table public.user_public_profiles to authenticated;
grant update (avatar_path) on table public.user_public_profiles to authenticated;
commit;
