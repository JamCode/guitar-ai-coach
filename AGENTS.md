# AGENTS.md

## Cursor Cloud specific instructions

### Project overview

Guitar AI Coach (吉他AI教练) — an AI-powered guitar learning platform with a **Vue 3 + Vite web frontend** and a **Python stdlib HTTP backend** (no framework). There is also a Flutter mobile app, but mobile builds require Xcode/iOS Simulator or Android SDK which are not available in Cloud Agent VMs.

### Services

| Service | How to run | Port | Notes |
|---|---|---|---|
| **Backend API** | `cd backend/code && BACKEND_HOST=0.0.0.0 python3 index.py` | 18080 | Pure Python; only dependency is `PyMySQL`. MySQL and DashScope API key are optional — most endpoints work without them. |
| **Frontend dev** | `cd frontend && npm run dev -- --host 0.0.0.0` | 5173 (Vite default) | Vue 3 SPA. Uses `npm ci` for dependency install (lockfile is `package-lock.json`). |

### Running lint / type-check / build

- **TypeScript check**: `cd frontend && npx tsc --noEmit`
- **Production build**: `cd frontend && npm run build` (runs `tsc && vite build`)
- **Backend import check**: `cd backend/code && python3 -c "import index"`

There is no dedicated ESLint config or Python linter configured in the repo.

### Key caveats

- The backend binds to `127.0.0.1` by default. Set `BACKEND_HOST=0.0.0.0` when you need it reachable from the browser in a Cloud VM.
- MySQL-dependent features (quiz, ear training, song chords) return HTTP 503 when `MYSQL_*` env vars are not set — this is expected and non-blocking for core chord features.
- `DASHSCOPE_API_KEY` is required for AI chord generation/explanation. Without it, the `/chords/generate` and `/chords/explain` endpoints return 500, but `/styles`, `/keys`, `/levels`, `/chords/transpose` all work.
- The Vite dev server proxying is **not** configured — the frontend calls the backend directly. In production, Nginx handles `/api/` proxying.
- Flutter app (`flutter_app/`) requires Dart SDK ^3.11.4 and native toolchains; skip in headless Cloud VMs.
