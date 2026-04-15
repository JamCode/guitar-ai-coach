#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLUTTER_APP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

KEY_ID="${TESTFLIGHT_KEY_ID:-}"
ISSUER_ID="${TESTFLIGHT_ISSUER_ID:-}"
KEY_FILE="${TESTFLIGHT_KEY_FILE:-}"
AUTO_BUMP_BUILD=1

usage() {
  cat <<'EOF'
一键构建并上传 iOS 到 TestFlight。

用法：
  ./tool/release_testflight.sh --key-id <KEY_ID> --issuer-id <ISSUER_ID> [--key-file <AuthKey.p8路径>] [--no-bump]

也支持环境变量：
  TESTFLIGHT_KEY_ID
  TESTFLIGHT_ISSUER_ID
  TESTFLIGHT_KEY_FILE   (可选，默认: ~/Documents/certs/AuthKey_<KEY_ID>.p8)

参数：
  --key-id      App Store Connect API Key ID
  --issuer-id   App Store Connect Issuer ID
  --key-file    .p8 私钥文件路径（可选）
  --no-bump     不自动递增 flutter_app/pubspec.yaml 的 build 号
  -h, --help    查看帮助
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --key-id)
      KEY_ID="${2:-}"
      shift 2
      ;;
    --issuer-id)
      ISSUER_ID="${2:-}"
      shift 2
      ;;
    --key-file)
      KEY_FILE="${2:-}"
      shift 2
      ;;
    --no-bump)
      AUTO_BUMP_BUILD=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "未知参数: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "${KEY_ID}" || -z "${ISSUER_ID}" ]]; then
  echo "缺少 --key-id 或 --issuer-id（或对应环境变量）" >&2
  usage
  exit 1
fi

if [[ -z "${KEY_FILE}" ]]; then
  KEY_FILE="$HOME/Documents/certs/AuthKey_${KEY_ID}.p8"
fi

if [[ ! -f "${KEY_FILE}" ]]; then
  echo "未找到私钥文件: ${KEY_FILE}" >&2
  exit 1
fi

cd "${FLUTTER_APP_DIR}"

if [[ "${AUTO_BUMP_BUILD}" -eq 1 ]]; then
  python3 - <<'PY'
from pathlib import Path
import re
import sys

pubspec_path = Path("pubspec.yaml")
content = pubspec_path.read_text(encoding="utf-8")
match = re.search(r"^(version:\s*\d+\.\d+\.\d+\+)(\d+)\s*$", content, flags=re.M)
if not match:
    print("无法解析 pubspec.yaml 的 version/build 号", file=sys.stderr)
    sys.exit(1)

prefix, build_str = match.group(1), match.group(2)
new_build = int(build_str) + 1
new_version_line = f"{prefix}{new_build}"
content = content[:match.start()] + new_version_line + content[match.end():]
pubspec_path.write_text(content, encoding="utf-8")
print(f"已自动递增 iOS build 号: {build_str} -> {new_build}")
PY
else
  echo "跳过 build 号自动递增（--no-bump）"
fi

echo ">>> flutter pub get"
flutter pub get

echo ">>> pod install"
(cd ios && pod install)

echo ">>> flutter build ipa"
flutter build ipa --export-options-plist=ios/ExportOptions.plist

IPA_PATH="$(python3 - <<'PY'
from pathlib import Path
ipas = sorted(Path("build/ios/ipa").glob("*.ipa"))
print(str(ipas[0]) if ipas else "")
PY
)"

if [[ -z "${IPA_PATH}" || ! -f "${IPA_PATH}" ]]; then
  echo "构建完成但未找到 IPA 文件（build/ios/ipa/*.ipa）" >&2
  exit 1
fi

mkdir -p "$HOME/.private_keys"
TARGET_KEY_FILE="$HOME/.private_keys/AuthKey_${KEY_ID}.p8"
cp "${KEY_FILE}" "${TARGET_KEY_FILE}"
chmod 600 "${TARGET_KEY_FILE}"

echo ">>> 上传到 App Store Connect (TestFlight)"
xcrun altool --upload-app --type ios \
  -f "${IPA_PATH}" \
  --apiKey "${KEY_ID}" \
  --apiIssuer "${ISSUER_ID}"

echo
echo "上传命令执行完成。"
echo "IPA: ${FLUTTER_APP_DIR}/${IPA_PATH}"
echo "请到 App Store Connect -> TestFlight 查看处理状态。"
