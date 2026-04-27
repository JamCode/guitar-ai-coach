#!/usr/bin/env bash
# 在 ECS 上于 chord_onnx 目录中后台启动: nohup ./run.sh >> "$LOG" 2>&1 &
# 单进程: conda activate 后 exec uvicorn（无额外 conda run 包装进程）
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"
if [[ ! -f "$HOME/miniconda3/etc/profile.d/conda.sh" ]]; then
  echo "未找到 Miniconda: $HOME/miniconda3" >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$HOME/miniconda3/etc/profile.d/conda.sh"
conda activate chord-onnx
exec uvicorn app:app --host 0.0.0.0 --port 8000
