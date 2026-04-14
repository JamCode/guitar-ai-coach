#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

ECS_HOST="${ECS_HOST:-47.110.78.65}"
ECS_USER="${ECS_USER:-wanghan}"
ECS_PATH="${ECS_PATH:-/home/wanghan/guitar-ai-coach}"
ECS_KEY="${ECS_KEY:-${ROOT_DIR}/my-ecs-key2.pem}"
LOCAL_DB_PORT="${LOCAL_DB_PORT:-13306}"
SERVICE_NAME="${SERVICE_NAME:-guitar-ai-coach-backend}"
BACKEND_ENV_PATH="${BACKEND_ENV_PATH:-${ECS_PATH}/deploy/ecs/backend.env}"
STRICT_HOST_KEY_CHECKING="${STRICT_HOST_KEY_CHECKING:-accept-new}"
FLYWAY_BASELINE_ON_MIGRATE="${FLYWAY_BASELINE_ON_MIGRATE:-true}"

usage() {
  cat <<'EOF'
一键部署 Python 后端到 ECS，并执行 Flyway DDL 对齐后重启服务。

用法：
  ./deploy/ecs/deploy_backend_with_flyway.sh

可选环境变量：
  ECS_HOST                   ECS 公网 IP（默认 47.110.78.65）
  ECS_USER                   SSH 用户（默认 wanghan）
  ECS_KEY                    SSH 私钥绝对路径（默认 <repo>/my-ecs-key2.pem）
  ECS_PATH                   服务器项目目录（默认 /home/wanghan/guitar-ai-coach）
  LOCAL_DB_PORT              本地 SSH 隧道端口（默认 13306）
  SERVICE_NAME               systemd 服务名（默认 guitar-ai-coach-backend）
  BACKEND_ENV_PATH           远程 backend.env 路径
  STRICT_HOST_KEY_CHECKING   SSH 严格主机校验策略（默认 accept-new）
  FLYWAY_BASELINE_ON_MIGRATE Flyway baselineOnMigrate（默认 true）
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ ! -f "${ECS_KEY}" ]]; then
  echo "ECS_KEY 不存在: ${ECS_KEY}" >&2
  exit 1
fi

if ! command -v flyway >/dev/null 2>&1; then
  echo "未检测到 flyway 命令，请先安装（例如: brew install flyway）" >&2
  exit 1
fi

if ! command -v rsync >/dev/null 2>&1; then
  echo "未检测到 rsync 命令，请先安装 rsync" >&2
  exit 1
fi

chmod 600 "${ECS_KEY}"

SSH_OPTS=(-i "${ECS_KEY}" -o "StrictHostKeyChecking=${STRICT_HOST_KEY_CHECKING}")
SSH_TARGET="${ECS_USER}@${ECS_HOST}"

echo ">>> 同步 backend/code 到 ECS"
rsync -avz -e "ssh ${SSH_OPTS[*]}" \
  "${ROOT_DIR}/backend/code/" "${SSH_TARGET}:${ECS_PATH}/backend/code/"

echo ">>> 同步 backend/database/flyway 到 ECS（便于运维对照）"
rsync -avz -e "ssh ${SSH_OPTS[*]}" \
  "${ROOT_DIR}/backend/database/flyway/" "${SSH_TARGET}:${ECS_PATH}/backend/database/flyway/"

echo ">>> 从 ECS 读取 MySQL 配置（${BACKEND_ENV_PATH}）"
MYSQL_JSON="$(ssh "${SSH_OPTS[@]}" "${SSH_TARGET}" "python3 - '${BACKEND_ENV_PATH}' <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
if not path.exists():
    print(f'backend.env not found: {path}', file=sys.stderr)
    sys.exit(1)

required = {
    'MYSQL_HOST': '',
    'MYSQL_PORT': '',
    'MYSQL_USER': '',
    'MYSQL_PASSWORD': '',
    'MYSQL_DATABASE': '',
}

for raw in path.read_text(encoding='utf-8').splitlines():
    line = raw.strip()
    if not line or line.startswith('#') or '=' not in line:
        continue
    key, value = line.split('=', 1)
    key = key.strip()
    if key in required:
        required[key] = value.strip().strip('\"').strip(\"'\")

missing = [k for k, v in required.items() if not v]
if missing:
    print(f'Missing MYSQL vars in {path}: {\", \".join(missing)}', file=sys.stderr)
    sys.exit(1)

print(json.dumps(required))
PY
")"

eval "$(
  python3 - "${MYSQL_JSON}" <<'PY'
import json
import shlex
import sys

data = json.loads(sys.argv[1])
for k, v in data.items():
    print(f"{k}={shlex.quote(v)}")
PY
)"

echo ">>> 建立 SSH 隧道到 MySQL: 127.0.0.1:${LOCAL_DB_PORT} -> ${MYSQL_HOST}:${MYSQL_PORT}"
ssh "${SSH_OPTS[@]}" -f -N -L "${LOCAL_DB_PORT}:${MYSQL_HOST}:${MYSQL_PORT}" "${SSH_TARGET}"

cleanup() {
  local pids
  pids="$(pgrep -f "ssh .*${LOCAL_DB_PORT}:${MYSQL_HOST}:${MYSQL_PORT} ${SSH_TARGET}" || true)"
  if [[ -n "${pids}" ]]; then
    echo "${pids}" | xargs kill >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

echo ">>> 执行 Flyway validate + migrate"
(
  cd "${ROOT_DIR}/backend/database/flyway"
  FLYWAY_URL="jdbc:mysql://127.0.0.1:${LOCAL_DB_PORT}/${MYSQL_DATABASE}?useSSL=false&characterEncoding=utf8" \
  FLYWAY_USER="${MYSQL_USER}" \
  FLYWAY_PASSWORD="${MYSQL_PASSWORD}" \
    flyway validate

  FLYWAY_URL="jdbc:mysql://127.0.0.1:${LOCAL_DB_PORT}/${MYSQL_DATABASE}?useSSL=false&characterEncoding=utf8" \
  FLYWAY_USER="${MYSQL_USER}" \
  FLYWAY_PASSWORD="${MYSQL_PASSWORD}" \
    flyway -baselineOnMigrate="${FLYWAY_BASELINE_ON_MIGRATE}" migrate
)

echo ">>> 重启后端服务并检查状态"
ssh "${SSH_OPTS[@]}" "${SSH_TARGET}" \
  "sudo systemctl restart ${SERVICE_NAME} && sudo systemctl is-active ${SERVICE_NAME}"

echo ">>> 服务器本机健康检查 /styles"
HTTP_CODE="$(ssh "${SSH_OPTS[@]}" "${SSH_TARGET}" \
  "curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1:18080/styles")"
echo "health check status code: ${HTTP_CODE}"

if [[ "${HTTP_CODE}" != "200" ]]; then
  echo "健康检查失败，期望 200，实际 ${HTTP_CODE}" >&2
  exit 1
fi

echo "部署完成：代码已同步、Flyway 已对齐、服务已重启且健康检查通过。"
