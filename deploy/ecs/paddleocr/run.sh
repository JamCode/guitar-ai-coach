#!/usr/bin/env bash
# 在 ECS 上使用已有 Miniconda 环境 paddleocr 启动 OCR 服务。
# 默认仅监听 127.0.0.1:18081，与后端 18080 错开；可按需改端口。
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONDA_SH="${CONDA_SH:-$HOME/miniconda3/etc/profile.d/conda.sh}"
if [[ -f "$CONDA_SH" ]]; then
  # shellcheck source=/dev/null
  source "$CONDA_SH"
else
  echo "未找到 $CONDA_SH，请先安装 Miniconda 或设置 CONDA_SH" >&2
  exit 1
fi
conda activate paddleocr
export FLAGS_enable_mkldnn=0
export PADDLEOCR_HOME="${PADDLEOCR_HOME:-$HOME/.paddleocr}"
HOST="${PADDLEOCR_BIND:-127.0.0.1}"
PORT="${PADDLEOCR_PORT:-18081}"
cd "$SCRIPT_DIR"
exec uvicorn app:app --host "$HOST" --port "$PORT" --workers 1
