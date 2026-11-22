-- The bootstrap role is superuser only to create the Supabase-like roles.
-- The migration itself is executed as a non-superuser postgres owner.
CREATE ROLE postgres LOGIN PASSWORD 'postgres' NOSUPERUSER NOCREATEDB NOCREATEROLE;
CREATE ROLE supabase_admin NOLOGIN SUPERUSER;
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE service_role NOLOGIN;

GRANT USAGE, CREATE ON SCHEMA public TO postgres;
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;

SET ROLE postgres;
CREATE TABLE public.existing_privilege_fixture (id bigint PRIMARY KEY);
GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN
ON TABLE public.existing_privilege_fixture TO anon, authenticated;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
GRANT TRUNCATE, REFERENCES, TRIGGER, MAINTAIN
ON TABLES TO anon, authenticated;
RESET ROLE;
