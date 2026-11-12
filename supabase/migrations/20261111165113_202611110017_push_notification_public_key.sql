create table if not exists public.push_settings (
 id smallint primary key default 1 check (id=1),
 public_key text not null,
 subject text not null default 'mailto:yisunshin715@gmail.com',
 updated_at timestamptz not null default now()
);
alter table public.push_settings enable row level security;
revoke all on public.push_settings from anon,authenticated;
grant select on public.push_settings to authenticated;
drop policy if exists push_settings_authenticated_read on public.push_settings;
create policy push_settings_authenticated_read on public.push_settings for select to authenticated using (true);
