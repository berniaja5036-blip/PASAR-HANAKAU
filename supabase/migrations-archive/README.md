# Archived SQL migration files

These 34 SQL files are retained unchanged for historical reference. They are deliberately outside `supabase/migrations/` so Supabase CLI does not treat legacy or already-applied untracked SQL as pending migrations.

Contents:
- 27 legacy numbered files from an earlier schema lineage.
- Two obsolete bootstrap files for the earlier `stores` / `role_memberships` schema.
- Five SQL files whose effects were applied outside the tracked migration history and verified in the current production catalog.

Do not execute these files or move them back into the active migrations directory without a separate schema-diff review.
