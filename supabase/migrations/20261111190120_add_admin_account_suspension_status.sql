alter table public.profiles
  add column if not exists account_status text not null default 'active',
  add column if not exists account_status_note text,
  add column if not exists account_status_updated_at timestamptz;
alter table public.profiles
  drop constraint if exists profiles_account_status_check;
alter table public.profiles
  add constraint profiles_account_status_check
  check (account_status in ('active','suspended'));
create index if not exists profiles_account_status_role_idx
  on public.profiles (account_status, role);
comment on column public.profiles.account_status is 'Administrative account state. Suspended accounts are blocked from signing in; transaction history remains preserved.';
comment on column public.profiles.account_status_note is 'Internal admin reason for account suspension; never shown publicly.';
