#!/usr/bin/env bash
set -euo pipefail

# Build frontend and sync static files to nginx web root.
# Usage:
#   ./deploy-to-nginx.sh
#   WEB_ROOT=/usr/share/nginx/html ./deploy-to-nginx.sh
#   SKIP_CI=1 ./deploy-to-nginx.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEB_ROOT="${WEB_ROOT:-/var/www/guitar-ai-coach}"
BUILD_DIR="${BUILD_DIR:-$SCRIPT_DIR/dist}"
SKIP_CI="${SKIP_CI:-0}"

echo "==> Frontend dir: $SCRIPT_DIR"
echo "==> Build dir:    $BUILD_DIR"
echo "==> Nginx root:   $WEB_ROOT"

cd "$SCRIPT_DIR"

if [[ "$SKIP_CI" == "1" ]]; then
  echo "==> SKIP_CI=1, skip npm ci"
else
  echo "==> Install dependencies (npm ci)"
  npm ci
fi

echo "==> Build frontend"
npm run build

if [[ ! -d "$BUILD_DIR" ]]; then
  echo "ERROR: build directory not found: $BUILD_DIR" >&2
  exit 1
fi

echo "==> Ensure nginx web root exists"
sudo mkdir -p "$WEB_ROOT"

echo "==> Sync dist to nginx web root"
sudo rsync -av --delete "$BUILD_DIR"/ "$WEB_ROOT"/

echo "==> Validate and reload nginx"
sudo nginx -t
sudo systemctl reload nginx

echo "Done."
