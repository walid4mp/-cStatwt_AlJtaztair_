# Deploy V1.4.1 safely with a shared PostgreSQL database

1. Do NOT change the existing `DATABASE_URL` in Render.
2. Do NOT add a new Render PostgreSQL database from this project.
3. Do NOT run `prisma db push --force-reset`.
4. Deploy this version. The startup script runs `prisma/safe-migrate.js` first.
5. The safe migration only adds nullable columns if they are missing. It does not drop, truncate, reset, or rewrite existing rows.
6. Then the API starts.
7. Check:
   `https://cstatwt-aljtaztair.onrender.com/health`
8. The expected response contains `ok: true` and `database: "ok"`.

## Important compatibility behavior
- Existing User rows may have `name = NULL`; API responses use `username` as the display-name fallback.
- Existing Comment rows may have `userId = NULL`; they are not guessed or reassigned.
- Existing Message rows may have `conversationId = NULL`; they are not guessed or reassigned.
- Existing Post/Notification/VerificationRequest legacy fields may be NULL.
- New records created by this API populate the new fields normally.

This is intentional: guessing relationships in a database shared with another application could corrupt the other application's data.
