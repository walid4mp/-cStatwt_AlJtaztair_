# V1.4 — Shared Database Safe Migration

This release is designed for a PostgreSQL database shared with another application.

## Safety rules
- Never run `prisma db push --force-reset`.
- The production start command does NOT run `prisma db push`.
- New legacy-compatibility fields are nullable so existing inserts from the other application are not forced to provide them.
- Follow and Like do not introduce a new `id` column; their existing composite uniqueness is retained.
- The safe migration is additive only.

## One-time migration
After a backup, run:

`npm run migrate:safe`

This adds only missing nullable columns. It does not drop, truncate, or reset tables.

## Important
The migration does not guess values for old Message.conversationId or Comment.userId because guessing could corrupt relationships used by the other application. Existing legacy rows remain valid with NULL in those compatibility fields; new records created by this application populate them normally.
