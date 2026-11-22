CREATE TABLE public.future_postgres_table (id bigint PRIMARY KEY);

DO $$
DECLARE
  role_name text;
  table_name text;
BEGIN
  FOREACH role_name IN ARRAY ARRAY['anon', 'authenticated'] LOOP
    FOREACH table_name IN ARRAY ARRAY[
      'public.existing_privilege_fixture',
      'public.future_postgres_table'
    ] LOOP
      IF has_table_privilege(role_name, table_name, 'TRUNCATE') THEN
        RAISE EXCEPTION '% unexpectedly has TRUNCATE on %', role_name, table_name;
      END IF;
      IF has_table_privilege(role_name, table_name, 'REFERENCES') THEN
        RAISE EXCEPTION '% unexpectedly has REFERENCES on %', role_name, table_name;
      END IF;
      IF has_table_privilege(role_name, table_name, 'TRIGGER') THEN
        RAISE EXCEPTION '% unexpectedly has TRIGGER on %', role_name, table_name;
      END IF;
      IF has_table_privilege(role_name, table_name, 'MAINTAIN') THEN
        RAISE EXCEPTION '% unexpectedly has MAINTAIN on %', role_name, table_name;
      END IF;
    END LOOP;
  END LOOP;

  IF NOT has_table_privilege('anon', 'public.existing_privilege_fixture', 'SELECT') THEN
    RAISE EXCEPTION 'Existing SELECT privilege was unexpectedly removed';
  END IF;
  IF NOT has_table_privilege('authenticated', 'public.existing_privilege_fixture', 'INSERT') THEN
    RAISE EXCEPTION 'Existing INSERT privilege was unexpectedly removed';
  END IF;
  IF NOT has_table_privilege('authenticated', 'public.existing_privilege_fixture', 'UPDATE') THEN
    RAISE EXCEPTION 'Existing UPDATE privilege was unexpectedly removed';
  END IF;
  IF NOT has_table_privilege('authenticated', 'public.existing_privilege_fixture', 'DELETE') THEN
    RAISE EXCEPTION 'Existing DELETE privilege was unexpectedly removed';
  END IF;
END
$$;
