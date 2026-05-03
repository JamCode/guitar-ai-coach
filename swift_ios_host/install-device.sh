#!/usr/bin/env bash
# 将 SwiftEarHost（测试/调试或 Release）编译并安装到已配对的本机 iPhone / iPad，可选自动启动。
#
# 前置条件：
#   - 本机已安装 Xcode 15+（含 xcodebuild、xcrun devicectl）
#   - 设备已用线连上或无线调试已配对，且「开发者模式」已打开（iPhone / iPad 相同）
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
#   ./install-device.sh --device "iPad"     # 同上，可装到 iPad（与 iPhone 同一 iOS 产物）
#   ./install-device.sh --ipad               # 自动选：仅保留名称里含 iPad 的已配对真机
#   ./install-device.sh --iphone             # 自动选：排除 iPad，在剩余已配对真机里选唯一一台（多为 iPhone）
#   DEVICE="iPhone" ./install-device.sh
#   ./install-device.sh --release           # Release 配置
#   ./install-device.sh --pull              # 先 git pull --rebase
#   ./install-device.sh --list              # 仅列出可用真机（Core Device）
#   ./install-device.sh --list --ipad       # 仅列出 iPad（名称/型号里含 iPad）
#   ./install-device.sh --list --iphone     # 仅列出非 iPad 的已配对真机（一般为 iPhone）
#   ./install-device.sh --no-iap-bypass     # Debug 真机安装时关闭本地内购绕过
#
# 说明：首次安装可能需在手机上「设置 → 通用 → VPN与设备管理」信任开发者证书。
# 本脚本可在 Debug 真机安装时注入 `LOCAL_IAP_BYPASS` 编译标记，仅用于本地开发排查。
# 该标记默认不会用于 Release/Archive/TestFlight/App Store。
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
BUNDLE_ID="com.wanghan.guitarhelper"

# ========== 仅自用一台机时可写死（省掉 export / install-device.local.env）==========
# 优先级低于：命令行 --device、环境变量 DEVICE / DEVICE_UDID / DEVELOPMENT_TEAM、install-device.local.env
# 换手机或换团队后请改下面两行；若推公共仓库建议改回空串或勿提交
DEFAULT_DEVELOPMENT_TEAM="7R8RS88G2M"
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

if [[ -z "${DEVELOPMENT_TEAM:-}" ]]; then
  # 尝试读取工程当前生效的 Team（来自 Xcode 本地签名设置）
  DETECTED_TEAM="$(xcodebuild -project "${PROJECT}" -scheme "${SCHEME}" -configuration Debug -showBuildSettings 2>/dev/null | awk '/DEVELOPMENT_TEAM =/{print $3; exit}')"
  if [[ -n "${DETECTED_TEAM}" ]]; then
    DEVELOPMENT_TEAM="${DETECTED_TEAM}"
  fi
fi

CONFIGURATION="Debug"
DO_PULL=0
LIST_ONLY=0
DEVICE_REF=""
ENABLE_LOCAL_IAP_BYPASS=1
# 自动发现多机时按设备类型过滤：空 | ipad | iphone
DEVICE_FAMILY_FILTER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pull) DO_PULL=1; shift ;;
    --release) CONFIGURATION="Release"; shift ;;
    --no-iap-bypass) ENABLE_LOCAL_IAP_BYPASS=0; shift ;;
    --list) LIST_ONLY=1; shift ;;
    --ipad)
      if [[ -n "${DEVICE_FAMILY_FILTER}" && "${DEVICE_FAMILY_FILTER}" != "ipad" ]]; then
        echo "不要同时使用 --ipad 与 --iphone" >&2
        exit 1
      fi
      DEVICE_FAMILY_FILTER="ipad"
      shift
      ;;
    --iphone)
      if [[ -n "${DEVICE_FAMILY_FILTER}" && "${DEVICE_FAMILY_FILTER}" != "iphone" ]]; then
        echo "不要同时使用 --ipad 与 --iphone" >&2
        exit 1
      fi
      DEVICE_FAMILY_FILTER="iphone"
      shift
      ;;
    --device)
      if [[ $# -lt 2 ]]; then echo "缺少 --device 参数值" >&2; exit 1; fi
      DEVICE_REF="$2"
      shift 2
      ;;
    -h|--help)
      sed -n '1,45p' "$0"
      exit 0
      ;;
    *)
      echo "未知参数: $1（支持 --pull --release --list --no-iap-bypass --ipad --iphone --device <名称或UDID>）" >&2
      exit 1
      ;;
  esac
done

if [[ "${LIST_ONLY}" -eq 1 ]]; then
  if [[ -z "${DEVICE_FAMILY_FILTER}" ]]; then
    echo "==> 已配对真机（devicectl）："
    xcrun devicectl list devices 2>/dev/null || true
  else
    echo "==> 已配对真机（仅 ${DEVICE_FAMILY_FILTER}，devicectl JSON 过滤）："
    JSON="$(mktemp)"
    if ! xcrun devicectl list devices --json-output "${JSON}" 2>/dev/null; then
      echo "无法执行 devicectl。" >&2
      rm -f "${JSON}"
      exit 1
    fi
    python3 - <<'PY' "${JSON}" "${DEVICE_FAMILY_FILTER}"
import json, sys
path, fam = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as f:
    data = json.load(f)
devices = data.get("result", {}).get("devices", [])

def is_ipad(dev):
    dp = dev.get("deviceProperties") or {}
    hw = dev.get("hardwareProperties") or {}
    name = (dp.get("name") or "").lower()
    model = (hw.get("modelName") or hw.get("marketingName") or "").lower()
    return "ipad" in name or "ipad" in model

def eligible(dev):
    hw = dev.get("hardwareProperties") or {}
    plat = hw.get("platform") or ""
    if plat not in ("iOS", "iPadOS"):
        return False
    if hw.get("reality") != "physical":
        return False
    cp = dev.get("connectionProperties") or {}
    if cp.get("pairingState") != "paired":
        return False
    if fam == "ipad" and not is_ipad(dev):
        return False
    if fam == "iphone" and is_ipad(dev):
        return False
    return True

fam = sys.argv[2]
for dev in devices:
    if not eligible(dev):
        continue
    name = (dev.get("deviceProperties") or {}).get("name", "?")
    print(f"{dev.get('identifier')}\t{name}")
PY
    rm -f "${JSON}"
  fi
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
  fam="${DEVICE_FAMILY_FILTER:-}"
  if [[ -n "${fam}" ]]; then
    echo "==> 自动检测本机唯一已配对 ${fam} 真机（iOS / iPadOS）…"
  else
    echo "==> 自动检测本机唯一已配对 iOS / iPadOS 真机…"
  fi
  JSON="$(mktemp)"
  if ! xcrun devicectl list devices --json-output "${JSON}" 2>/dev/null; then
    echo "无法执行 devicectl，请确认已安装 Xcode 命令行工具。" >&2
    rm -f "${JSON}"
    exit 1
  fi
  DEVICE_REF="$(python3 - <<'PY' "${JSON}" "${fam}"
import json, sys
path = sys.argv[1]
fam = (sys.argv[2] if len(sys.argv) > 2 else "") or ""

def is_ipad(dev):
    dp = dev.get("deviceProperties") or {}
    hw = dev.get("hardwareProperties") or {}
    name = (dp.get("name") or "").lower()
    model = (hw.get("modelName") or hw.get("marketingName") or "").lower()
    return "ipad" in name or "ipad" in model

with open(path, encoding="utf-8") as f:
    data = json.load(f)
devices = data.get("result", {}).get("devices", [])
eligible = []
for dev in devices:
    hw = dev.get("hardwareProperties") or {}
    plat = hw.get("platform") or ""
    if plat not in ("iOS", "iPadOS"):
        continue
    if hw.get("reality") != "physical":
        continue
    cp = dev.get("connectionProperties") or {}
    if cp.get("pairingState") != "paired":
        continue
    if fam == "ipad" and not is_ipad(dev):
        continue
    if fam == "iphone" and is_ipad(dev):
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
    echo "未找到符合条件的已配对真机。请用数据线连接、在 Xcode 里配对，或使用 --device / DEVICE 指定。" >&2
    echo "提示: ./install-device.sh --list   或   ./install-device.sh --list --ipad" >&2
    exit 1
  fi
  if [[ "${DEVICE_REF}" == "MULTI" ]]; then
    echo "" >&2
    echo "检测到多台符合条件的已配对真机，请指定其一，例如:" >&2
    echo "  ./install-device.sh --device '<Identifier或设备名>'" >&2
    if [[ -n "${fam}" ]]; then
      echo "  或先: ./install-device.sh --list --${fam}" >&2
    fi
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
if [[ -n "${CHORD_ONNX_APP_TOKEN:-}" ]]; then
  XCODE_ARGS+=(CHORD_ONNX_APP_TOKEN="${CHORD_ONNX_APP_TOKEN}")
fi
if [[ "${CONFIGURATION}" == "Debug" && "${ENABLE_LOCAL_IAP_BYPASS}" -eq 1 ]]; then
  echo "==> Debug 真机安装启用 LOCAL_IAP_BYPASS（仅本地开发）"
  XCODE_ARGS+=(SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) LOCAL_IAP_BYPASS')
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
