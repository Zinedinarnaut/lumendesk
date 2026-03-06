# LumenDesk Marketplace API

Vercel-hosted TypeScript API for LumenDesk marketplace feeds, uploads, and preview metadata.

## Stack

- Next.js Route Handlers (Node runtime)
- Neon Postgres (`@neondatabase/serverless`) for metadata
- `@vercel/blob` for uploaded video files
- Apple identity token verification (`jose`) for protected uploads

## Endpoints

- `GET /api/health`
- `GET /api/marketplace`
- `GET /api/wallpapers`
- `GET /api/wallpapers/:id`
- `POST /api/wallpapers/:id/install`
- `GET /wallpapers.json`
- `POST /api/upload`
- `POST /upload`

`GET /api/marketplace` supports:

- `q` (search title/author/summary)
- `kind` (`web|video|gradient|shader`)
- `tag`
- `featured` (`true|false`)
- `sort` (`featured|popular|latest`)
- `page`, `perPage`

## Environment Variables

- `POSTGRES_URL` (required)
- `BLOB_READ_WRITE_TOKEN` (required for file uploads)
- `REQUIRE_APPLE_AUTH` (default `true`; set `false` to disable token checks)
- `APPLE_BUNDLE_ID` (recommended for audience check)
- `APPLE_SERVICE_ID` (optional additional audience)
- `APPLE_CLIENT_ID` (optional additional audience)
- `MARKETPLACE_ADMIN_TOKEN` (optional; enables privileged upload flags like `featured` and custom `status`)

## Local Run

```bash
npm install
npm run dev
```

## Deploy

Deploy this folder to Vercel:

```bash
bash /Users/zinedinarnaut/.codex/skills/vercel-deploy/scripts/deploy.sh ./marketplace-api
```
