#!/usr/bin/env bash
# 将 SwiftEarHost（测试/调试或 Release）编译并安装到已配对的本机 iPhone，可选自动启动。
#
# 前置条件：
#   - 本机已安装 Xcode 15+（含 xcodebuild、xcrun devicectl）
#   - iPhone 已用线连上或无线调试已配对，且「开发者模式」已打开
#   - Apple Developer：本机 Xcode 已登录账号，且工程能自动签名；或设置 DEVELOPMENT_TEAM
#
# 用法：
#   在脚本里填 DEFAULT_DEVELOPMENT_TEAM / DEFAULT_DEVICE_ID（仅自用一台机时最省事），或：
#   export DEVELOPMENT_TEAM=你的10位TeamID
#   ./install-device.sh
#
# 也可用：swift_ios_host/install-device.local.env（已 gitignore），示例见 install-device.local.env.example
#   ./install-device.sh --device E0846AB6-0894-5A3F-AA3F-3885DB11B978
#   ./install-device.sh --device "iPhone"   # devicectl 支持设备名称
#   DEVICE="iPhone" ./install-device.sh
#   ./install-device.sh --release           # Release 配置
#   ./install-device.sh --pull              # 先 git pull --rebase
#   ./install-device.sh --list              # 仅列出可用真机（Core Device）
#
# 说明：首次安装可能需在手机上「设置 → 通用 → VPN与设备管理」信任开发者证书。
#
# Team ID 在哪里看（10 位字母数字）：
#   • Xcode → Settings（或 Preferences）→ Accounts → 选中左侧 Apple ID → 右侧 Team 名称后面括号里
#   • 或浏览器打开 https://developer.apple.com/account → Membership → Team ID
#
# 设备 Identifier：终端执行  ./install-device.sh --list  或  xcrun devicectl list devices  看第三列

set -euo pipefail

HOST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${HOST_DIR}/.." && pwd)"
PROJECT="${HOST_DIR}/SwiftEarHost.xcodeproj"
SCHEME="SwiftEarHost"
BUNDLE_ID="com.jamcode.swift-ear-host"

# ========== 仅自用一台机时可写死（省掉 export / install-device.local.env）==========
# 优先级低于：命令行 --device、环境变量 DEVICE / DEVICE_UDID / DEVELOPMENT_TEAM、install-device.local.env
# 换手机或换团队后请改下面两行；若推公共仓库建议改回空串或勿提交
DEFAULT_DEVELOPMENT_TEAM="S7GN5K6W2H"
DEFAULT_DEVICE_ID="E0846AB6-0894-5A3F-AA3F-3885DB11B978"

LOCAL_ENV="${HOST_DIR}/install-device.local.env"
if [[ -f "${LOCAL_ENV}" ]]; then
  echo "==> 读取本地配置: ${LOCAL_ENV}"
  set -a
  # shellcheck disable=SC1090
  source "${LOCAL_ENV}"
  set +a
fi

if [[ -z "${DEVELOPMENT_TEAM:-}" && -n "${DEFAULT_DEVELOPMENT_TEAM}" ]]; then
  DEVELOPMENT_TEAM="${DEFAULT_DEVELOPMENT_TEAM}"
fi

CONFIGURATION="Debug"
DO_PULL=0
LIST_ONLY=0
DEVICE_REF=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pull) DO_PULL=1; shift ;;
    --release) CONFIGURATION="Release"; shift ;;
    --list) LIST_ONLY=1; shift ;;
    --device)
      if [[ $# -lt 2 ]]; then echo "缺少 --device 参数值" >&2; exit 1; fi
      DEVICE_REF="$2"
      shift 2
      ;;
    -h|--help)
      sed -n '1,35p' "$0"
      exit 0
      ;;
    *)
      echo "未知参数: $1（支持 --pull --release --list --device <名称或UDID>）" >&2
      exit 1
      ;;
  esac
done

if [[ "${LIST_ONLY}" -eq 1 ]]; then
  echo "==> 已配对真机（devicectl）："
  xcrun devicectl list devices 2>/dev/null || true
  exit 0
fi

if [[ "${DO_PULL}" -eq 1 ]]; then
  echo "==> git pull（${REPO_ROOT}）"
  git -C "${REPO_ROOT}" pull --rebase
fi

if [[ -z "${DEVICE_REF}" ]]; then
  DEVICE_REF="${DEVICE:-${DEVICE_UDID:-}}"
fi

if [[ -z "${DEVICE_REF}" && -n "${DEFAULT_DEVICE_ID}" ]]; then
  DEVICE_REF="${DEFAULT_DEVICE_ID}"
fi

if [[ -z "${DEVICE_REF}" ]]; then
  echo "==> 自动检测本机唯一已配对 iOS 真机…"
  JSON="$(mktemp)"
  if ! xcrun devicectl list devices --json-output "${JSON}" 2>/dev/null; then
    echo "无法执行 devicectl，请确认已安装 Xcode 命令行工具。" >&2
    rm -f "${JSON}"
    exit 1
  fi
  DEVICE_REF="$(python3 - <<'PY' "${JSON}"
import json, sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = json.load(f)
devices = data.get("result", {}).get("devices", [])
eligible = []
for dev in devices:
    hw = dev.get("hardwareProperties") or {}
    if hw.get("platform") != "iOS":
        continue
    if hw.get("reality") != "physical":
        continue
    cp = dev.get("connectionProperties") or {}
    if cp.get("pairingState") != "paired":
        continue
    eligible.append(dev)
if not eligible:
    print("NONE", end="")
elif len(eligible) > 1:
    print("MULTI", end="")
    for d in eligible:
        name = (d.get("deviceProperties") or {}).get("name", "?")
        print(f"\n  {d.get('identifier')}  ({name})", file=sys.stderr, end="")
else:
    print(eligible[0]["identifier"], end="")
PY
)"
  rm -f "${JSON}"
  if [[ -z "${DEVICE_REF}" || "${DEVICE_REF}" == "NONE" ]]; then
    echo "未找到已配对的 iOS 真机。请连接手机、在 Xcode 里配对一次，或使用 --device / DEVICE 指定。" >&2
    echo "提示: ./install-device.sh --list" >&2
    exit 1
  fi
  if [[ "${DEVICE_REF}" == "MULTI" ]]; then
    echo "" >&2
    echo "检测到多台已配对真机，请用其一设置环境变量或传参，例如:" >&2
    echo "  DEVICE='<Identifier或设备名>' ./install-device.sh" >&2
    echo "  ./install-device.sh --device '<Identifier或设备名>'" >&2
    exit 1
  fi
fi

echo "==> 使用设备: ${DEVICE_REF}"

if [[ -z "${DEVELOPMENT_TEAM:-}" ]]; then
  echo "" >&2
  echo "错误: SwiftEarHost 工程未在仓库里写死 Development Team，命令行真机构建必须提供 Team ID。" >&2
  echo "" >&2
  echo "任选一种方式：" >&2
  echo "  1) 本脚本顶部 DEFAULT_DEVELOPMENT_TEAM='你的10位TeamID'" >&2
  echo "  2) 本次终端：  export DEVELOPMENT_TEAM=你的10位TeamID  && ./install-device.sh" >&2
  echo "  3) 本地文件：  cp install-device.local.env.example install-device.local.env 并填写" >&2
  echo "" >&2
  echo "Team ID：Xcode → Settings → Accounts → Apple ID → Team 名称后括号内 10 位；" >&2
  echo "或 https://developer.apple.com/account → Membership。" >&2
  exit 1
fi

DERIVED="${DERIVED_DATA_PATH:-/tmp/SwiftEarHostDeviceBuild-${USER}}"
echo "==> xcodebuild（${CONFIGURATION} / generic iOS）→ ${DERIVED}"
rm -rf "${DERIVED}"

XCODE_ARGS=(
  -project "${PROJECT}"
  -scheme "${SCHEME}"
  -configuration "${CONFIGURATION}"
  -destination "generic/platform=iOS"
  -derivedDataPath "${DERIVED}"
  -allowProvisioningUpdates
  CODE_SIGN_STYLE=Automatic
)
if [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then
  XCODE_ARGS+=(DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM}")
fi

xcodebuild "${XCODE_ARGS[@]}" build

APP="${DERIVED}/Build/Products/${CONFIGURATION}-iphoneos/SwiftEarHost.app"
if [[ ! -d "${APP}" ]]; then
  echo "未找到产物: ${APP}" >&2
  exit 1
fi

echo "==> 安装到设备"
xcrun devicectl device install app --device "${DEVICE_REF}" "${APP}"

echo "==> 启动 ${BUNDLE_ID}"
xcrun devicectl device process launch --device "${DEVICE_REF}" "${BUNDLE_ID}" || true

echo "完成。若图标灰显或无法打开，请在手机上信任本机开发者证书。"
