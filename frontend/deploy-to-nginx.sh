#!/usr/bin/env bash
set -euo pipefail

# Build frontend and sync static files to nginx web root（本机有 nginx 时用）.
# ECS 上请用 wanghan 直接 rsync 到 ~/guitar-ai-coach/site/，见 deploy/ecs/README.md。
# Usage:
#   ./deploy-to-nginx.sh
#   WEB_ROOT=/usr/share/nginx/html ./deploy-to-nginx.sh
#   WEB_ROOT=/home/wanghan/guitar-ai-coach/site ./deploy-to-nginx.sh   # 在 ECS 本机以 wanghan 执行时可不设 sudo（目录可写）
#   EXCLUDE_WELL_KNOWN=1 ./deploy-to-nginx.sh   # rsync --delete 时保留 .well-known/**

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEB_ROOT="${WEB_ROOT:-/usr/share/nginx/html}"
BUILD_DIR="${BUILD_DIR:-$SCRIPT_DIR/dist}"
SKIP_CI="${SKIP_CI:-0}"
USE_SUDO="${USE_SUDO:-1}"
EXCLUDE_WELL_KNOWN="${EXCLUDE_WELL_KNOWN:-1}"
RELOAD_NGINX="${RELOAD_NGINX:-1}"

SUDO_CMD=""
if [[ "$USE_SUDO" == "1" ]]; then
  SUDO_CMD="sudo"
fi

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
$SUDO_CMD mkdir -p "$WEB_ROOT"

echo "==> Sync dist to nginx web root"
RSYNC_ARGS=(-av --delete)
if [[ "$EXCLUDE_WELL_KNOWN" == "1" ]]; then
  RSYNC_ARGS+=(--exclude ".well-known/**")
  echo "==> Keep .well-known/** (exclude from delete)"
fi
$SUDO_CMD rsync "${RSYNC_ARGS[@]}" "$BUILD_DIR"/ "$WEB_ROOT"/

if [[ "$RELOAD_NGINX" == "1" ]]; then
  echo "==> Validate and reload nginx"
  $SUDO_CMD nginx -t
  $SUDO_CMD systemctl reload nginx
else
  echo "==> Skip nginx reload (RELOAD_NGINX=0)"
fi

echo "Done."
