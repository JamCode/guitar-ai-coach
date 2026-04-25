#!/usr/bin/env bash
# 基于当前仓库代码编译 SwiftEarHost，安装到 iOS 模拟器。
#
# 重要（内购本地测试）：
# - 命令行 `simctl launch` 无法稳定复现 Xcode Run Action 的 StoreKit 注入行为。
# - 因此本脚本默认执行到「安装完成」后自动打开 Xcode 工程，提示用 Cmd+R 启动，
#   以确保使用 StoreKitConfig.storekit（不弹真实 Apple ID）。
# - 若只调普通功能，可传 --simctl-launch 强制直接启动（不推荐用于内购）。
#
# 用法：
#   ./run-simulator.sh
#   SIMULATOR_UDID=<udid> ./run-simulator.sh
#   ./run-simulator.sh --pull
#   ./run-simulator.sh --simctl-launch      # 普通功能调试；内购可能走真实 App Store
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
DO_SIMCTL_LAUNCH=0
for arg in "$@"; do
  case "${arg}" in
    --pull) DO_PULL=1 ;;
    --simctl-launch) DO_SIMCTL_LAUNCH=1 ;;
    -h|--help)
      sed -n '1,80p' "$0"
      exit 0
      ;;
    *)
      echo "未知参数: ${arg}（支持 --pull / --simctl-launch）" >&2
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

if [[ ! -f "${HOST_DIR}/LocalPackages/onnxruntime-swift-package-manager/Package.swift" ]]; then
  echo "缺少本地 Onnx Swift 包目录（不依赖 Xcode 每次访问 GitHub）。" >&2
  echo "请执行：cd \"${HOST_DIR}\" && ./bootstrap-onnx-local-package.sh --from-dir <目录>" >&2
  exit 1
fi
# shellcheck disable=SC1091
source "${HOST_DIR}/scripts/onnx-local-env.sh"

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
echo "    Simulator UDID: ${UDID}"
echo "    Bundle ID: ${BUNDLE_ID}"
echo "    StoreKitConfig: ${STOREKIT_CONFIG}"
echo "    StoreKitConfig exists: YES"
STOREKIT_FLAG_SUPPORTED=0
if xcodebuild -help 2>&1 | /usr/bin/python3 -c 'import sys; print("1" if "-storeKitConfiguration" in sys.stdin.read() else "0")' | grep -q '^1$'; then
  STOREKIT_FLAG_SUPPORTED=1
fi
echo "    xcodebuild -storeKitConfiguration supported: $([[ ${STOREKIT_FLAG_SUPPORTED} -eq 1 ]] && echo YES || echo NO)"
echo "    Launch mode: $([[ ${DO_SIMCTL_LAUNCH} -eq 1 ]] && echo 'simctl (IAP not guaranteed)' || echo 'Xcode Cmd+R required for IAP')"

echo "==> 打开 Simulator"
open -a Simulator 2>/dev/null || true

echo "==> 启动模拟器 ${UDID}（若已启动则忽略错误）"
xcrun simctl boot "${UDID}" 2>/dev/null || true

echo "==> xcodebuild（Debug / iphonesimulator, 带 StoreKitConfig）"
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
  echo "⚠️ 当前 xcodebuild 不支持 -storeKitConfiguration（命令行限制）。"
  echo "⚠️ 将继续完成 build+install；内购测试必须在 Xcode 中 Cmd+R 才能走本地 StoreKit。"
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
  echo "⚠️ 使用 simctl 直接启动（内购可能仍弹 Apple ID）：${BUNDLE_ID}"
  xcrun simctl launch --terminate-running-process "${UDID}" "${BUNDLE_ID}"
  echo "完成（simctl 模式）。"
  exit 0
fi

echo "==> 已完成构建与安装。"
echo "==> 为确保 StoreKit 本地内购生效，请在 Xcode 中运行（Cmd+R）："
echo "    1) 打开工程: ${PROJECT}"
echo "    2) 选择模拟器 UDID: ${UDID}"
echo "    3) 确认 Scheme Run > Options 绑定 ${STOREKIT_CONFIG}"
echo "    4) 按 Cmd+R 启动"
open -a Xcode "${PROJECT}" 2>/dev/null || true
