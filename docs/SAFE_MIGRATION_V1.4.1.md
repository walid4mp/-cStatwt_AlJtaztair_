# V1.4.1 — Shared PostgreSQL Safe Migration

This version fixes the `P2022 User.name does not exist` situation without resetting the shared database.

## What changed
- Migration checks the exact `public."User"` table through PostgreSQL catalogs.
- Uses `ADD COLUMN IF NOT EXISTS` for additive nullable fields only.
- Verifies every column inside the same transaction before commit.
- Verifies every column again after commit from a fresh Prisma connection.
- Logs the actual database target (`current_database`, schema, server address/port) without printing secrets.
- Aborts before the API starts if the expected `public."User"` table is not found.
- Never uses `prisma db push --force-reset`.
- Never drops or renames tables.
- Existing rows are not rewritten.

## Fields ensured
- User.name
- Comment.userId
- Post.body
- Message.conversationId
- Message.body
- Notification.title
- Notification.body
- VerificationRequest.reason
- VerificationRequest.updatedAt

## Important for the shared database
Do not change `DATABASE_URL` on the Render service. Do not run a database reset. The migration is intentionally additive and nullable.

## Expected Render log
The deployment should contain:

`Safe migration completed and verified. No tables were dropped or reset.`

If it fails, the log will show the database target and the exact field that could not be verified. Do not retry with `--force-reset`.
