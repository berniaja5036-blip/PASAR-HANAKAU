create table if not exists public.android_push_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  fcm_token text not null unique,
  platform text not null default 'android',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists android_push_tokens_user_id_idx on public.android_push_tokens(user_id);
alter table public.android_push_tokens enable row level security;
