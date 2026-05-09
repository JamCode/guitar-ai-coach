#!/usr/bin/env bash
# 在本机（能 SSH 进 ECS 的机器）执行：同步本目录到服务器、安装依赖、冒烟测试、后台启动 OCR 服务。
# 用法：
#   ECS_KEY="$HOME/Documents/guitar-ai-coach/my-ecs-key2.pem" ./push-and-setup.sh
# 可选环境变量：ECS_USER（默认 wanghan）、ECS_HOST（默认 47.110.78.65）

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ECS_USER="${ECS_USER:-wanghan}"
ECS_HOST="${ECS_HOST:-47.110.78.65}"
ECS="${ECS_USER}@${ECS_HOST}"

if [[ -z "${ECS_KEY:-}" ]]; then
  echo "请设置 ECS_KEY 为私钥绝对路径，例如：" >&2
  echo "  ECS_KEY=\"\$HOME/Documents/guitar-ai-coach/my-ecs-key2.pem\" $0" >&2
  exit 1
fi
chmod 600 "$ECS_KEY"

SSH=(ssh -i "$ECS_KEY" -o StrictHostKeyChecking=accept-new)
RSYNC=(rsync -avz -e "ssh -i $ECS_KEY -o StrictHostKeyChecking=accept-new")

echo "==> rsync -> ${ECS}:~/guitar-ai-coach/deploy/ecs/paddleocr/"
"${SSH[@]}" "$ECS" "mkdir -p ~/guitar-ai-coach/deploy/ecs/paddleocr"
"${RSYNC[@]}" "$SCRIPT_DIR/" "$ECS:~/guitar-ai-coach/deploy/ecs/paddleocr/"

echo "==> remote: pip + smoke + start uvicorn"
"${SSH[@]}" "$ECS" bash << 'REMOTE'
set -euo pipefail
if [[ ! -f "$HOME/miniconda3/etc/profile.d/conda.sh" ]]; then
  echo "未找到 Miniconda：$HOME/miniconda3" >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$HOME/miniconda3/etc/profile.d/conda.sh"
conda activate paddleocr
echo "    paddle / paddleocr install..."
python -m pip install -q "paddlepaddle==2.6.2" -i https://www.paddlepaddle.org.cn/packages/stable/cpu/
cd "$HOME/guitar-ai-coach/deploy/ecs/paddleocr"
python -m pip install -q -r requirements-paddleocr.txt -i https://pypi.tuna.tsinghua.edu.cn/simple
echo "    smoke test OCR..."
python << 'PY'
import os
import tempfile

import cv2
import numpy as np
from paddleocr import PaddleOCR

img = np.zeros((32, 64, 3), dtype=np.uint8) + 255
fd, p = tempfile.mkstemp(suffix=".png")
os.close(fd)
cv2.imwrite(p, img)
ocr = PaddleOCR(use_angle_cls=True, lang="ch", use_gpu=False, show_log=False)
r = ocr.ocr(p, cls=True)
os.remove(p)
assert r is not None
print("    smoke_ok")
PY
echo "    stop old listener on 18081 (if any)"
pkill -f "uvicorn app:app --host 127.0.0.1 --port 18081" 2>/dev/null || true
sleep 1
chmod +x run.sh
nohup ./run.sh >> "$HOME/paddleocr-serve.log" 2>&1 &
sleep 2
echo "    health:"
curl -sS "http://127.0.0.1:18081/health" && echo ""
echo "    log: tail -f ~/paddleocr-serve.log"
REMOTE

echo "==> done"
