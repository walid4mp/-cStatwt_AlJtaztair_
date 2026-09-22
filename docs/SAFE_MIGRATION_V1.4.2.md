# V1.4.2 Shared DB Safe

- Does not add or require `User.name` in the shared `User` table.
- Stores Sawt Aljazair display names in isolated `SawtAljazairProfile`.
- Keeps existing shared tables and rows untouched except nullable additive columns already required by the API.
- Adds `GET /` so the Render primary URL returns service JSON instead of `Route not found`.
- Keeps `GET /health`.
- No database reset/drop.
