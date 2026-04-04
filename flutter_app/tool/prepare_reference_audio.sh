#!/usr/bin/env bash
# 从前端依赖 `tonejs-instrument-guitar-acoustic-mp3` 拷贝六根空弦 MP3 到 Flutter assets。
# 在仓库根执行，或先 `cd frontend && npm ci` 确保 node_modules 存在。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$(cd "$ROOT/../.." && pwd)"
SRC="$REPO_ROOT/frontend/node_modules/tonejs-instrument-guitar-acoustic-mp3"
DST="$ROOT/assets/audio/tone_guitar_reference"
if [[ ! -d "$SRC" ]]; then
  echo "缺少: $SRC （请在 frontend 目录执行 npm install）" >&2
  exit 1
fi
mkdir -p "$DST"
for f in E2 A2 D3 G3 B3 E4; do
  cp "$SRC/${f}.mp3" "$DST/${f}.mp3"
done
echo "OK -> $DST"
