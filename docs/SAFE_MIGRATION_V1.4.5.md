# V1.4.5 — Shared DB registration fix

- Registration no longer relies on Prisma `User.create()` for the shared `User` table.
- It performs an explicit INSERT that always supplies the existing required `User.displayName`.
- No DROP/RESET and no schema changes to `User` are performed.
- `SawtAljazairProfile` stores app-specific `wilaya` and display-name metadata.
- Optional test account creation is controlled only by `TEST_ACCOUNT_EMAIL` and `TEST_ACCOUNT_PASSWORD`.
- If those two variables are absent, no test account is created.

## Test account
Set on Render:
`TEST_ACCOUNT_EMAIL`
`TEST_ACCOUNT_PASSWORD`
`TEST_ACCOUNT_USERNAME` (optional)
`TEST_ACCOUNT_NAME` (optional)
`TEST_ACCOUNT_WILAYA` (optional)

On restart the account is created only if the email and username do not already exist. The password is never printed to logs.
