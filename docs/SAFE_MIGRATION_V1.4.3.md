# Sawt Aljazair V1.4.3 — Shared DB Safe

This patch isolates both display name and wilaya from the shared `User` table.

- `User.name` is not required.
- `User.wilaya` is not required.
- `SawtAljazairProfile.displayName` stores the app display name.
- `SawtAljazairProfile.wilaya` stores the app wilaya.
- Existing shared tables are not dropped or reset.
- Registration creates the shared `User` row and app profile atomically in one transaction.
- The root route `/` remains a health-style JSON response.

Do not run `prisma db push --force-reset` or any reset command against the shared database.
