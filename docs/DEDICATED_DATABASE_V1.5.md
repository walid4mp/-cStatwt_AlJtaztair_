# Sawt Aljazair V1.5 — Dedicated Database

This release assumes `DATABASE_URL` points to a PostgreSQL database dedicated to Sawt Aljazair.

Required Render variable:
- `DEDICATED_DATABASE=true`

On startup the backend runs `prisma db push --skip-generate` to create/synchronize the complete Prisma schema, including `Report`, `Evidence`, `Post`, `User`, messages, notifications, lost/found, etc. It does not use the old shared-database additive migration.

Test account variables are optional. Defaults:
- Email: sawt.test.2026@example.com
- Password: SawtTest@2026!
- Username: sawt_test_2026
- Name: Sawt Aljazair Test
- Wilaya: وهران

Do not point this release at the old shared database unless the complete schema is intentionally deployed there.
