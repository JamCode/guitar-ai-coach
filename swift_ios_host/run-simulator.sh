#!/usr/bin/env bash
# 基于当前仓库代码编译 SwiftEarHost，安装到 iOS 模拟器并启动。
#
# 默认行为（推荐日常开发）：
# - Debug + iOS Simulator 产物，安装后用 simctl 直接拉起 App（无需再开 Xcode 点 Run）。
# - 「扒歌」在模拟器 Debug 下由 App 内 #if DEBUG + targetEnvironment(simulator) 自动绕过内购；
#   真机 / Release / App Store 不受影响。
#
# StoreKit 本地配置文件（.storekit）联调：
# - 命令行 xcodebuild 多数版本不支持 -storeKitConfiguration；若需 Xcode Run 注入 StoreKit，
#   请使用：./run-simulator.sh --open-xcode
#
# 用法：
#   ./run-simulator.sh
#   SIMULATOR_UDID=<udid> ./run-simulator.sh
#   ./run-simulator.sh --pull
#   ./run-simulator.sh --open-xcode   # 仅构建安装后打开 Xcode，用 Cmd+R 跑 StoreKit 配置
#
# 依赖：xcodebuild、xcrun simctl、python3。

set -euo pipefail

HOST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${HOST_DIR}/.." && pwd)"
PROJECT="${HOST_DIR}/SwiftEarHost.xcodeproj"
SCHEME="SwiftEarHost"
BUNDLE_ID="com.wanghan.guitarhelper"
PRODUCT_ID="com.wanghan.guitarhelper.transcription_unlock"
SPM_CLONES_DIR="${SPM_CLONES_DIR:-${HOME}/Library/Caches/SwiftEarHost-spm-repos}"
DEFAULT_SIMULATOR_UDID="${SIMULATOR_UDID:-F877F638-03AC-4C4B-ADDF-5631C27FEB05}"
DERIVED="${DERIVED_DATA_PATH:-/tmp/SwiftEarHostSimBuild-${USER}}"

# 优先使用 host 目录下 .storekit；其次仓库根目录。
STOREKIT_CONFIG="${STOREKIT_CONFIG:-}"
if [[ -z "${STOREKIT_CONFIG}" ]]; then
  if [[ -f "${HOST_DIR}/StoreKitConfig.storekit" ]]; then
    STOREKIT_CONFIG="${HOST_DIR}/StoreKitConfig.storekit"
  elif [[ -f "${REPO_ROOT}/StoreKitConfig.storekit" ]]; then
    STOREKIT_CONFIG="${REPO_ROOT}/StoreKitConfig.storekit"
  else
    STOREKIT_CONFIG="${HOST_DIR}/StoreKitConfig.storekit"
  fi
fi

DO_PULL=0
# 默认直接 simctl 启动；仅 StoreKit Xcode 注入时用 --open-xcode
DO_SIMCTL_LAUNCH=1
for arg in "$@"; do
  case "${arg}" in
    --pull) DO_PULL=1 ;;
    --open-xcode) DO_SIMCTL_LAUNCH=0 ;;
    --simctl-launch)
      # 兼容旧参数：现为默认行为，可忽略
      DO_SIMCTL_LAUNCH=1
      ;;
    -h|--help)
      sed -n '1,90p' "$0"
      exit 0
      ;;
    *)
      echo "未知参数: ${arg}（支持 --pull / --open-xcode）" >&2
      exit 1
      ;;
  esac
done

UDID="${SIMULATOR_UDID:-${DEFAULT_SIMULATOR_UDID}}"

if [[ "${DO_PULL}" -eq 1 ]]; then
  echo "==> git pull（仓库根: ${REPO_ROOT}）"
  git -C "${REPO_ROOT}" pull --rebase
fi

mkdir -p "${SPM_CLONES_DIR}"

if [[ ! -f "${STOREKIT_CONFIG}" ]]; then
  echo "❌ StoreKitConfig 不存在：${STOREKIT_CONFIG}" >&2
  echo "请创建并保存 StoreKit 配置文件后重试。" >&2
  exit 1
fi

# 校验 .storekit 中的产品与类型
python3 - <<'PY' "${STOREKIT_CONFIG}" "${PRODUCT_ID}"
import json, sys
path, pid = sys.argv[1], sys.argv[2]
with open(path, 'r', encoding='utf-8') as f:
    data = json.load(f)
products = data.get('products', [])
match = [p for p in products if p.get('productID') == pid]
if not match:
    print(f"❌ StoreKitConfig 缺少商品: {pid}", file=sys.stderr)
    sys.exit(2)
if match[0].get('type') != 'NonConsumable':
    print(f"❌ 商品类型错误: {match[0].get('type')}（应为 NonConsumable）", file=sys.stderr)
    sys.exit(3)
print(f"==> StoreKitConfig 商品校验通过: {pid} / {match[0].get('type')}")
PY

# 校验代码内 Product ID
if ! python3 - <<'PY' "${HOST_DIR}/Sources/Transcription/Purchases/PurchaseManager.swift" "${PRODUCT_ID}"
import sys
path, pid = sys.argv[1], sys.argv[2]
text = open(path, 'r', encoding='utf-8').read()
needle = f'"{pid}"'
if needle not in text:
    print(f"❌ PurchaseManager.swift 未找到 Product ID: {pid}", file=sys.stderr)
    sys.exit(1)
print(f"==> 代码 Product ID 校验通过: {pid}")
PY
then
  exit 1
fi

echo "==> 启动参数检查"
echo "    Project: ${PROJECT}"
echo "    Scheme: ${SCHEME}"
echo "    Configuration: Debug（含 SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG）"
echo "    Simulator UDID: ${UDID}"
echo "    Bundle ID: ${BUNDLE_ID}"
echo "    StoreKitConfig: ${STOREKIT_CONFIG}"
echo "    StoreKitConfig exists: YES"
STOREKIT_FLAG_SUPPORTED=0
if xcodebuild -help 2>&1 | /usr/bin/python3 -c 'import sys; print("1" if "-storeKitConfiguration" in sys.stdin.read() else "0")' | grep -q '^1$'; then
  STOREKIT_FLAG_SUPPORTED=1
fi
echo "    xcodebuild -storeKitConfiguration supported: $([[ ${STOREKIT_FLAG_SUPPORTED} -eq 1 ]] && echo YES || echo NO)"
echo "    Launch: $([[ ${DO_SIMCTL_LAUNCH} -eq 1 ]] && echo 'simctl（默认）' || echo '打开 Xcode（--open-xcode）')"
echo "    扒歌内购：模拟器 Debug 包由 App 编译开关绕过；真机/Release 不绕过"

echo "==> 打开 Simulator"
open -a Simulator 2>/dev/null || true

echo "==> 启动模拟器 ${UDID}（若已启动则忽略错误）"
xcrun simctl boot "${UDID}" 2>/dev/null || true

echo "==> xcodebuild（Debug / iphonesimulator）"
rm -rf "${DERIVED}/Build"
mkdir -p "${DERIVED}"

if [[ "${STOREKIT_FLAG_SUPPORTED}" -eq 1 ]]; then
  xcodebuild \
    -project "${PROJECT}" \
    -scheme "${SCHEME}" \
    -configuration Debug \
    -destination "platform=iOS Simulator,id=${UDID}" \
    -derivedDataPath "${DERIVED}" \
    -clonedSourcePackagesDirPath "${SPM_CLONES_DIR}" \
    -storeKitConfiguration "${STOREKIT_CONFIG}" \
    build
else
  echo "⚠️ 当前 xcodebuild 不支持 -storeKitConfiguration（命令行限制）；已跳过该参数。"
  xcodebuild \
    -project "${PROJECT}" \
    -scheme "${SCHEME}" \
    -configuration Debug \
    -destination "platform=iOS Simulator,id=${UDID}" \
    -derivedDataPath "${DERIVED}" \
    -clonedSourcePackagesDirPath "${SPM_CLONES_DIR}" \
    build
fi

APP="${DERIVED}/Build/Products/Debug-iphonesimulator/SwiftEarHost.app"
if [[ ! -d "${APP}" ]]; then
  echo "❌ 未找到产物: ${APP}" >&2
  exit 1
fi

echo "==> 安装到模拟器"
xcrun simctl uninstall "${UDID}" "${BUNDLE_ID}" 2>/dev/null || true
xcrun simctl install "${UDID}" "${APP}"

if [[ "${DO_SIMCTL_LAUNCH}" -eq 1 ]]; then
  echo "==> simctl 启动 ${BUNDLE_ID}"
  xcrun simctl launch --terminate-running-process "${UDID}" "${BUNDLE_ID}"
  echo "完成。"
  echo "提示：扒歌在「模拟器 + Debug」下会显示「模拟器调试：已绕过购买」并可直接从相册导入。"
  exit 0
fi

echo "==> 已完成构建与安装。"
echo "==> 若需 Xcode Run 注入 StoreKit（.storekit），请 Cmd+R："
echo "    工程: ${PROJECT}  ·  模拟器 UDID: ${UDID}"
open -a Xcode "${PROJECT}" 2>/dev/null || true
