# LumenDesk

LumenDesk is a native SwiftUI macOS wallpaper engine for Apple Silicon Macs.

## What It Does

- Renders animated wallpapers on every connected display using desktop-level windows.
- Supports four source types per display:
  - Animated gradient presets
  - GPU Metal shader presets
  - Local looping video files
  - Live web pages (WKWebView)
- Adds community features:
  - Marketplace feed + upload flow
  - Dedicated Marketplace page
  - GitHub wallpaper pack search and install
  - Dedicated GitHub Packs page
  - Dedicated Studio page
  - Sign in with Apple for marketplace identity/auth headers
- Adds performance features:
  - Automatic GPU throttling based on CPU load
- Includes per-display controls:
  - Source selection
  - Scale mode (Fill / Fit / Stretch)
  - Video mute / volume / playback speed
- Includes global engine controls:
  - Pause/resume
  - Pause on battery
  - Pause when fullscreen apps are detected
  - Global FPS cap used by web and Metal shader wallpapers
  - Effective FPS display (after auto-throttling)
  - Launch at login
- Saves settings automatically to:
  - `~/Library/Application Support/LumenDesk/settings.json`

## Requirements

- macOS 14+
- Xcode 15+

## Run

```bash
xcodebuild -project LumenDesk.xcodeproj -scheme LumenDesk -configuration Debug build
open LumenDesk.xcodeproj
```

Run the `LumenDesk` scheme in Xcode.

## Regenerate Project

If you edit `project.yml`, regenerate the Xcode project:

```bash
xcodegen generate
```

## Project Layout

- `Sources/LumenDesk/App` - app entry and scenes
- `Sources/LumenDesk/Models` - app and display settings models
- `Sources/LumenDesk/Services` - engine, persistence, marketplace, GitHub packs, auth, CPU monitoring
- `Sources/LumenDesk/Platform` - desktop wallpaper window integration
- `Sources/LumenDesk/Renderers` - Metal, video, and web wallpaper renderers
- `Sources/LumenDesk/UI` - settings UI and wallpaper SwiftUI views
- `Sources/LumenDesk/Utilities` - shared helpers
- `marketplace-api` - Vercel-hosted TypeScript API with Postgres + Blob upload support

## Marketplace API (Vercel + Postgres)

The backend lives in `marketplace-api`.

Setup:

```bash
cd marketplace-api
npm install
npm run build
```

Required environment variables (Vercel project):

- `POSTGRES_URL`
- `BLOB_READ_WRITE_TOKEN` (required for video file uploads)
- `APPLE_BUNDLE_ID` (recommended for Apple token audience checks)
- `REQUIRE_APPLE_AUTH` (`true` by default, set `false` only for local testing)

Key routes:

- `GET /api/health`
- `GET /api/wallpapers`
- `POST /api/upload`
- `GET /wallpapers.json`
- `POST /upload`

Claimable Vercel deploy:

```bash
bash /Users/zinedinarnaut/.codex/skills/vercel-deploy/scripts/deploy.sh ./marketplace-api
```

## Wallpaper Pack Format

GitHub packs can include `pack.json`:

```json
{
  "name": "My Pack",
  "wallpapers": [
    { "id": "one", "title": "Neon City", "type": "video", "path": "videos/neon.mp4" },
    { "id": "two", "title": "Canvas", "type": "web", "url": "https://example.com/canvas" }
  ]
}
```

If `pack.json` is missing, video files in the repo are auto-discovered.

## Troubleshooting

- `SMAppServiceErrorDomain Code=1 Operation not permitted`: launch-at-login registration is limited by signing/runtime context. Build and run as a normal `.app` from Xcode.
- Local web URLs like `*.localhost` are supported; the app automatically retries `localhost`/`127.0.0.1` fallbacks.

## Marketplace Auth (Apple)

- The app uses native Sign in with Apple in the Marketplace panel.
- Upload requests include:
  - `Authorization: Bearer <apple_identity_token>`
  - `X-Apple-User-ID: <apple_user_id>`
- Your marketplace backend should verify the Apple identity token server-side against Apple's public keys before accepting uploads.
- With a paid Apple Developer account, use your own bundle ID/team and keep the Sign in with Apple capability enabled.

## Notes

- This implementation avoids private APIs.
- Desktop-level window behavior can vary across Spaces/multi-display setups depending on macOS updates.
- Music reactive mode is intentionally disabled in this build to avoid CoreAudio overload issues.
