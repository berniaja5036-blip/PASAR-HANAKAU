-- Restrict profile writes to the fields actually used by the client.
-- Profiles are created by the trusted auth trigger; anonymous clients need no access.
begin;
revoke all privileges on table public.profiles from anon, public;
revoke insert on table public.profiles from authenticated;

-- The avatar upsert may insert its owner id and path, but must never reassign
-- the row or alter timestamps. Existing reads remain available to signed-in users.
revoke insert, update on table public.user_public_profiles from authenticated;
grant insert (user_id, avatar_path) on table public.user_public_profiles to authenticated;
grant update (avatar_path) on table public.user_public_profiles to authenticated;
commit;
