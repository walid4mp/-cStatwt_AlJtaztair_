# Media storage

For local development the API stores files under `backend/uploads`.
For production configure the S3-compatible variables in `.env` (Cloudflare R2 works).
The mobile app never receives private exact coordinates; public map points are rounded by the API.
