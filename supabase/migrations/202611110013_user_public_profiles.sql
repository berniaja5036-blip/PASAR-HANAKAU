begin;

create table public.user_public_profiles (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  display_name text not null default '',
  avatar_path text,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  constraint user_public_profiles_avatar_path_owner
    check (avatar_path is null or split_part(avatar_path, '/', 1) = user_id::text)
);

alter table public.user_public_profiles enable row level security;

grant select, insert, update on public.user_public_profiles to authenticated;

create policy user_public_profiles_read_authenticated
  on public.user_public_profiles
  for select
  to authenticated
  using (true);

create policy user_public_profiles_insert_own
  on public.user_public_profiles
  for insert
  to authenticated
  with check (user_id = (select auth.uid()));

create policy user_public_profiles_update_own
  on public.user_public_profiles
  for update
  to authenticated
  using (user_id = (select auth.uid()))
  with check (
    user_id = (select auth.uid())
    and (avatar_path is null or split_part(avatar_path, '/', 1) = (select auth.uid())::text)
  );

create or replace function public.sync_user_public_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.user_public_profiles (user_id, display_name)
  values (new.id, coalesce(new.full_name, ''))
  on conflict (user_id) do update
    set display_name = excluded.display_name,
        updated_at = pg_catalog.now();
  return new;
end;
$$;

revoke all on function public.sync_user_public_profile() from public, anon, authenticated;

create trigger sync_user_public_profile_after_profile_change
  after insert or update of full_name on public.profiles
  for each row execute function public.sync_user_public_profile();

insert into public.user_public_profiles (user_id, display_name)
select id, coalesce(full_name, '')
from public.profiles
on conflict (user_id) do update
  set display_name = excluded.display_name,
      updated_at = pg_catalog.now();

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'profile-avatars',
  'profile-avatars',
  true,
  2097152,
  array['image/jpeg', 'image/png', 'image/webp']::text[]
)
on conflict (id) do nothing;

create policy profile_avatars_owner_upload
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'profile-avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy profile_avatars_owner_delete
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'profile-avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

commit;