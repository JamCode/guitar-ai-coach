#!/usr/bin/env bash
# 在本机（能 SSH 进 ECS 的机器）执行：同步 backend/chord_onnx_server、安装依赖、停旧 8000、启动 uvicorn、健康检查。
# 用法:
#   ECS_KEY="$HOME/Documents/guitar-ai-coach/my-ecs-key2.pem" ./push-and-setup.sh
# 可选: ECS_USER（默认 wanghan）、ECS_HOST（默认 47.110.78.65）、CHORD_ONNX_LOG（默认见远端 heredoc）

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CHORD_DIR="$REPO_ROOT/backend/chord_onnx_server"
ECS_USER="${ECS_USER:-wanghan}"
ECS_HOST="${ECS_HOST:-47.110.78.65}"
ECS="${ECS_USER}@${ECS_HOST}"

if [[ -z "${ECS_KEY:-}" ]]; then
  echo "请设置 ECS_KEY 为私钥绝对路径，例如：" >&2
  echo "  ECS_KEY=\"\$HOME/Documents/guitar-ai-coach/my-ecs-key2.pem\" $0" >&2
  exit 1
fi
if [[ ! -d "$CHORD_DIR" ]]; then
  echo "未找到: $CHORD_DIR" >&2
  exit 1
fi
chmod 600 "$ECS_KEY"

SSH=(ssh -i "$ECS_KEY" -o StrictHostKeyChecking=accept-new)
RSYNC=(rsync -avz -e "ssh -i $ECS_KEY -o StrictHostKeyChecking=accept-new")

echo "==> rsync -> ${ECS}:~/guitar-ai-coach/backend/chord_onnx_server/"
"${SSH[@]}" "$ECS" "mkdir -p ~/guitar-ai-coach/backend/chord_onnx_server ~/guitar-ai-coach/logs"
"${RSYNC[@]}" \
  --exclude '.venv' --exclude '__pycache__' --exclude '*.pyc' \
  "$CHORD_DIR/" "$ECS:~/guitar-ai-coach/backend/chord_onnx_server/"
# 未使用 --delete，避免本机未包含的 models/*.onnx 在远端被误删

echo "==> remote: pip, restart uvicorn(8000), health"
"${SSH[@]}" "$ECS" bash << 'REMOTE'
set -euo pipefail
if [[ ! -f "$HOME/miniconda3/etc/profile.d/conda.sh" ]]; then
  echo "未找到 Miniconda：$HOME/miniconda3" >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$HOME/miniconda3/etc/profile.d/conda.sh"
conda activate chord-onnx
cd "$HOME/guitar-ai-coach/backend/chord_onnx_server"
python -m pip install -q -r requirements.txt -i https://pypi.tuna.tsinghua.edu.cn/simple
chmod +x run.sh 2>/dev/null || true

CHORD_LOG="${CHORD_ONNX_LOG:-$HOME/guitar-ai-coach/logs/chord_onnx.log}"
mkdir -p "$(dirname "$CHORD_LOG")"

echo "    stop old listener on 8000 (fuser or pkill)"
if command -v fuser >/dev/null 2>&1; then
  fuser -k 8000/tcp 2>/dev/null || true
else
  pkill -f "uvicorn app:app --host 0.0.0.0 --port 8000" 2>/dev/null || true
  pkill -f "conda run -n chord-onnx uvicorn" 2>/dev/null || true
fi
sleep 2

echo "    start: nohup ./run.sh -> $CHORD_LOG"
nohup ./run.sh >> "$CHORD_LOG" 2>&1 &
sleep 2
echo "    health:"
curl -sS --max-time 10 "http://127.0.0.1:8000/health" && echo ""
echo "    log: tail -f $CHORD_LOG"
REMOTE

echo "==> done"
