-- Keep public API roles limited to ordinary row-level operations.
-- RLS and the existing per-table DML grants remain unchanged.
REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN
ON ALL TABLES IN SCHEMA public
FROM anon, authenticated;

-- Public tables in this project are owned by postgres. Keep future tables
-- created by the migration/database owner free of these unnecessary privileges.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN
ON TABLES FROM anon, authenticated;
