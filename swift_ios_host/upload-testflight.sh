#!/usr/bin/env bash
# 将 SwiftEarHost 归档并上传到 TestFlight（App Store Connect）。
#
# 前置条件：
#   - 本机已安装 Xcode（xcodebuild / xcrun altool 可用）
#   - 签名可用（Xcode 可本机 Archive 成功）
#   - 已在 App Store Connect 创建 API Key（Key ID + Issuer ID + .p8）
#
# 用法：
#   ./upload-testflight.sh
#   ./upload-testflight.sh --pull
#   ./upload-testflight.sh --archive-only
#   ./upload-testflight.sh --no-bump-build
#   ASC_KEY_ID=XXXXX ASC_ISSUER_ID=XXXXX ASC_KEY_PATH=/abs/path/AuthKey_XXXXX.p8 ./upload-testflight.sh
#
# 本地配置（推荐）：swift_ios_host/upload-testflight.local.env（已 gitignore）
# 示例见 upload-testflight.local.env.example

set -euo pipefail

HOST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${HOST_DIR}/.." && pwd)"
PROJECT="${HOST_DIR}/SwiftEarHost.xcodeproj"
SCHEME="SwiftEarHost"
CONFIGURATION="Release"

# 可按需写死（仅自用）。优先级低于环境变量与 local env。
DEFAULT_DEVELOPMENT_TEAM="7R8RS88G2M"
DEFAULT_ASC_KEY_ID=""
DEFAULT_ASC_ISSUER_ID=""
DEFAULT_ASC_KEY_PATH=""

LOCAL_ENV="${HOST_DIR}/upload-testflight.local.env"
if [[ -f "${LOCAL_ENV}" ]]; then
  echo "==> 读取本地配置: ${LOCAL_ENV}"
  set -a
  # shellcheck disable=SC1090
  source "${LOCAL_ENV}"
  set +a
fi

DO_PULL=0
ARCHIVE_ONLY=0
AUTO_BUMP_BUILD=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pull) DO_PULL=1; shift ;;
    --archive-only) ARCHIVE_ONLY=1; shift ;;
    --no-bump-build) AUTO_BUMP_BUILD=0; shift ;;
    -h|--help)
      sed -n '1,35p' "$0"
      exit 0
      ;;
    *)
      echo "未知参数: $1（支持 --pull --archive-only --no-bump-build）" >&2
      exit 1
      ;;
  esac
done

if [[ "${DO_PULL}" -eq 1 ]]; then
  echo "==> git pull（${REPO_ROOT}）"
  git -C "${REPO_ROOT}" pull --rebase
fi

if [[ -z "${DEVELOPMENT_TEAM:-}" && -n "${DEFAULT_DEVELOPMENT_TEAM}" ]]; then
  DEVELOPMENT_TEAM="${DEFAULT_DEVELOPMENT_TEAM}"
fi
if [[ -z "${ASC_KEY_ID:-}" && -n "${DEFAULT_ASC_KEY_ID}" ]]; then
  ASC_KEY_ID="${DEFAULT_ASC_KEY_ID}"
fi
if [[ -z "${ASC_ISSUER_ID:-}" && -n "${DEFAULT_ASC_ISSUER_ID}" ]]; then
  ASC_ISSUER_ID="${DEFAULT_ASC_ISSUER_ID}"
fi
if [[ -z "${ASC_KEY_PATH:-}" && -n "${DEFAULT_ASC_KEY_PATH}" ]]; then
  ASC_KEY_PATH="${DEFAULT_ASC_KEY_PATH}"
fi

if [[ -z "${DEVELOPMENT_TEAM:-}" ]]; then
  DETECTED_TEAM="$(xcodebuild -project "${PROJECT}" -scheme "${SCHEME}" -configuration "${CONFIGURATION}" -showBuildSettings 2>/dev/null | awk '/DEVELOPMENT_TEAM =/{print $3; exit}')"
  if [[ -n "${DETECTED_TEAM}" ]]; then
    DEVELOPMENT_TEAM="${DETECTED_TEAM}"
  fi
fi

if [[ -z "${DEVELOPMENT_TEAM:-}" ]]; then
  echo "错误: 未设置 DEVELOPMENT_TEAM，无法归档签名。" >&2
  echo "可在 upload-testflight.local.env 里设置，或 export DEVELOPMENT_TEAM=XXXXXXXXXX" >&2
  exit 1
fi

if [[ -z "${ASC_KEY_ID:-}" || -z "${ASC_ISSUER_ID:-}" ]]; then
  echo "错误: 缺少 ASC_KEY_ID / ASC_ISSUER_ID。" >&2
  echo "请在 upload-testflight.local.env 设置，或临时 export 后再执行。" >&2
  exit 1
fi

if [[ -z "${ASC_KEY_PATH:-}" ]]; then
  ASC_KEY_PATH="$HOME/Documents/certs/AuthKey_${ASC_KEY_ID}.p8"
fi

if [[ ! -f "${ASC_KEY_PATH}" ]]; then
  echo "错误: 找不到 API Key 文件: ${ASC_KEY_PATH}" >&2
  echo "请设置 ASC_KEY_PATH 指向 AuthKey_<KEY_ID>.p8" >&2
  exit 1
fi

mkdir -p "$HOME/.private_keys"
cp "${ASC_KEY_PATH}" "$HOME/.private_keys/AuthKey_${ASC_KEY_ID}.p8"
chmod 600 "$HOME/.private_keys/AuthKey_${ASC_KEY_ID}.p8"

echo "==> 读取版本信息"
MARKETING_VERSION="$(xcodebuild -project "${PROJECT}" -scheme "${SCHEME}" -configuration "${CONFIGURATION}" -showBuildSettings 2>/dev/null | awk '/MARKETING_VERSION =/{print $3; exit}')"
BUILD_NUMBER="$(xcodebuild -project "${PROJECT}" -scheme "${SCHEME}" -configuration "${CONFIGURATION}" -showBuildSettings 2>/dev/null | awk '/CURRENT_PROJECT_VERSION =/{print $3; exit}')"
echo "    MARKETING_VERSION=${MARKETING_VERSION:-unknown}"
echo "    CURRENT_PROJECT_VERSION=${BUILD_NUMBER:-unknown}"

ARCHIVE_BUILD_NUMBER="${BUILD_NUMBER:-}"
if [[ -n "${BUILD_NUMBER_OVERRIDE:-}" ]]; then
  ARCHIVE_BUILD_NUMBER="${BUILD_NUMBER_OVERRIDE}"
elif [[ "${AUTO_BUMP_BUILD}" -eq 1 ]]; then
  # 采用时间戳作为本次归档 Build，确保每次上传均唯一（不改动仓库文件）。
  ARCHIVE_BUILD_NUMBER="$(date +%y%m%d%H%M)"
fi

if [[ -z "${ARCHIVE_BUILD_NUMBER}" ]]; then
  echo "错误: 无法确定 Build 号，请设置 BUILD_NUMBER_OVERRIDE 或在 Xcode 中填写 Build。" >&2
  exit 1
fi
echo "    ARCHIVE_BUILD_NUMBER=${ARCHIVE_BUILD_NUMBER}"

STAMP="$(date +%Y%m%d-%H%M%S)"
WORKDIR="${WORK_DIR:-/tmp/SwiftEarHostTestFlight-${USER}/${STAMP}}"
ARCHIVE_PATH="${WORKDIR}/SwiftEarHost.xcarchive"
EXPORT_DIR="${WORKDIR}/export"
EXPORT_PLIST="${WORKDIR}/ExportOptions.plist"

mkdir -p "${WORKDIR}" "${EXPORT_DIR}"

cat > "${EXPORT_PLIST}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>app-store</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>teamID</key>
  <string>${DEVELOPMENT_TEAM}</string>
  <key>uploadBitcode</key>
  <false/>
  <key>uploadSymbols</key>
  <true/>
</dict>
</plist>
PLIST

echo "==> Archive（${CONFIGURATION}）"
xcodebuild \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -destination "generic/platform=iOS" \
  -archivePath "${ARCHIVE_PATH}" \
  -allowProvisioningUpdates \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM}" \
  CURRENT_PROJECT_VERSION="${ARCHIVE_BUILD_NUMBER}" \
  archive

echo "==> Export IPA"
xcodebuild \
  -exportArchive \
  -archivePath "${ARCHIVE_PATH}" \
  -exportPath "${EXPORT_DIR}" \
  -exportOptionsPlist "${EXPORT_PLIST}" \
  -allowProvisioningUpdates

IPA_PATH="$(ls "${EXPORT_DIR}"/*.ipa 2>/dev/null | awk 'NR==1{print}')"
if [[ -z "${IPA_PATH}" ]]; then
  echo "错误: 未导出 IPA（目录: ${EXPORT_DIR}）" >&2
  exit 1
fi

echo "==> IPA 已生成: ${IPA_PATH}"

if [[ "${ARCHIVE_ONLY}" -eq 1 ]]; then
  echo "已按 --archive-only 结束（未上传）。"
  exit 0
fi

echo "==> 上传 TestFlight（altool）"
xcrun altool --upload-app --type ios \
  -f "${IPA_PATH}" \
  --apiKey "${ASC_KEY_ID}" \
  --apiIssuer "${ASC_ISSUER_ID}"

echo "上传命令已完成。请到 App Store Connect → TestFlight 查看处理状态。"
