-- Public catalog reads remain available to anonymous visitors.
-- Anonymous clients must never be able to mutate application records directly.
do $migration$
declare
  t record;
begin
  for t in
    select schemaname, tablename
    from pg_tables
    where schemaname='public'
  loop
    execute format(
      'revoke insert, update, delete on table %I.%I from anon',
      t.schemaname, t.tablename
    );
  end loop;
end
$migration$;
