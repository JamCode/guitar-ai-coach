#!/usr/bin/env bash
# 基于当前仓库代码编译 SwiftEarHost，安装到 iOS 模拟器并启动。
#
# 用法：
#   ./run-simulator.sh              # 使用默认模拟器 UDID（见下方 DEFAULT_SIMULATOR_UDID）
#   SIMULATOR_UDID=<udid> ./run-simulator.sh
#   ./run-simulator.sh --pull       # 先 git pull 再编译（在仓库根目录执行 pull）
#
# 依赖：Xcode 命令行工具（xcodebuild、xcrun simctl）、已安装的 iOS Simulator 运行时。

set -euo pipefail

HOST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${HOST_DIR}/.." && pwd)"
PROJECT="${HOST_DIR}/SwiftEarHost.xcodeproj"
SCHEME="SwiftEarHost"
BUNDLE_ID="com.wanghan.guitarhelper"

# 默认：此前会话中使用的「iPhone 16 Flutter」；可改成本机 `xcrun simctl list devices available` 里的 UDID
DEFAULT_SIMULATOR_UDID="${SIMULATOR_UDID:-F877F638-03AC-4C4B-ADDF-5631C27FEB05}"

DO_PULL=0
for arg in "$@"; do
  case "${arg}" in
    --pull) DO_PULL=1 ;;
    -h|--help)
      sed -n '1,20p' "$0"
      exit 0
      ;;
    *)
      echo "未知参数: ${arg}（支持 --pull）" >&2
      exit 1
      ;;
  esac
done

if [[ "${DO_PULL}" -eq 1 ]]; then
  echo "==> git pull（仓库根: ${REPO_ROOT}）"
  git -C "${REPO_ROOT}" pull --rebase
fi

UDID="${SIMULATOR_UDID:-${DEFAULT_SIMULATOR_UDID}}"
DERIVED="${DERIVED_DATA_PATH:-/tmp/SwiftEarHostSimBuild-${USER}}"

echo "==> 打开 Simulator"
open -a Simulator 2>/dev/null || true

echo "==> 启动模拟器 ${UDID}（若已启动则忽略错误）"
xcrun simctl boot "${UDID}" 2>/dev/null || true

echo "==> xcodebuild（Debug / iphonesimulator）"
rm -rf "${DERIVED}"
xcodebuild \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=${UDID}" \
  -derivedDataPath "${DERIVED}" \
  build

APP="${DERIVED}/Build/Products/Debug-iphonesimulator/SwiftEarHost.app"
if [[ ! -d "${APP}" ]]; then
  echo "未找到产物: ${APP}" >&2
  exit 1
fi

echo "==> 安装到模拟器"
xcrun simctl install "${UDID}" "${APP}"

echo "==> 启动 ${BUNDLE_ID}"
xcrun simctl launch "${UDID}" "${BUNDLE_ID}"

echo "完成。若窗口未在前台，请手动切到 Simulator。"
