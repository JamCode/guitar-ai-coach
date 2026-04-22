#!/usr/bin/env bash
# 准备本地 OnnxRuntime Swift 包：目录不提交 git（见 .gitignore）。
#
# 设计目标：你**不能稳定访问 GitHub** 时仍能工作——优先用 U 盘/内网拷贝整目录，
# 或在本脚本里用镜像 URL / 预下载的 zip，而不是依赖默认 github.com。
#
# 用法（在 swift_ios_host 目录下）：
#   ./bootstrap-onnx-local-package.sh --help
#
# 常见场景：
#   A) 完全离线：在有网的机器上 git clone 或下载 release zip，把整个目录拷到 U 盘，再：
#        ./bootstrap-onnx-local-package.sh --from-dir /Volumes/U盘/onnxruntime-swift-package-manager
#      或打成 tar.gz 带过来：
#        ./bootstrap-onnx-local-package.sh --from-archive ~/Downloads/onnx-spm.tgz
#
#   B) 仅能访问镜像：克隆前设置（示例，按你实际镜像改）：
#        export ONNXRUNTIME_SPM_GIT_URL="https://你的镜像/microsoft/onnxruntime-swift-package-manager.git"
#        ./bootstrap-onnx-local-package.sh
#
#   C) 二进制 zip 也已离线：放到某目录并命名与官方一致，然后：
#        export ONNXRUNTIME_ZIPS_DIR="/path/to/dir"   # 内含两个 zip 文件名见下方常量
#        ./bootstrap-onnx-local-package.sh --from-dir ...   # 或已有 Package 时只加 --with-zips
#        ./bootstrap-onnx-local-package.sh --with-zips      # 仅补 zip，不克隆
#
#   D) 默认（能访问 GitHub）：不加参数，等价于 git clone 官方仓库。

set -euo pipefail

ORT_TAG="1.24.2"
ORT_ZIP_NAME="pod-archive-onnxruntime-c-1.24.2.zip"
ORT_EXT_ZIP_NAME="pod-archive-onnxruntime-extensions-c-0.13.0.zip"
DEFAULT_SPM_GIT_URL="https://github.com/microsoft/onnxruntime-swift-package-manager.git"
DEFAULT_POD_ZIP_URL="https://download.onnxruntime.ai/${ORT_ZIP_NAME}"
DEFAULT_EXT_ZIP_URL="https://download.onnxruntime.ai/${ORT_EXT_ZIP_NAME}"

HOST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="${HOST_DIR}/LocalPackages/onnxruntime-swift-package-manager"
VENDOR_DIR="${PKG_DIR}/.vendor"

FROM_DIR=""
FROM_ARCHIVE=""
DO_ZIPS=0
DO_HELP=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) DO_HELP=1; shift ;;
    --from-dir)
      [[ $# -lt 2 ]] && { echo "缺少 --from-dir 路径" >&2; exit 1; }
      FROM_DIR="$2"
      shift 2
      ;;
    --from-archive)
      [[ $# -lt 2 ]] && { echo "缺少 --from-archive 路径" >&2; exit 1; }
      FROM_ARCHIVE="$2"
      shift 2
      ;;
    --with-zips) DO_ZIPS=1; shift ;;
    *)
      echo "未知参数: $1（见 --help）" >&2
      exit 1
      ;;
  esac
done

if [[ "${DO_HELP}" -eq 1 ]]; then
  sed -n '2,25p' "$0"
  echo ""
  echo "参数: [--from-dir 路径] [--from-archive 路径.zip|.tar.gz] [--with-zips]"
  echo "环境变量: ONNXRUNTIME_SPM_GIT_URL | ONNXRUNTIME_POD_ZIP_URL | ONNXRUNTIME_EXT_ZIP_URL | ONNXRUNTIME_ZIPS_DIR"
  exit 0
fi

if [[ -n "${FROM_DIR}" && -n "${FROM_ARCHIVE}" ]]; then
  echo "不要同时使用 --from-dir 与 --from-archive" >&2
  exit 1
fi

copy_tree_into_pkg() {
  local src="$1"
  if [[ ! -f "${src}/Package.swift" ]]; then
    echo "源目录缺少 Package.swift: ${src}" >&2
    exit 1
  fi
  mkdir -p "${HOST_DIR}/LocalPackages"
  rm -rf "${PKG_DIR}"
  mkdir -p "${PKG_DIR}"
  # 保留符号链接与权限；GNU rsync 常见，macOS 自带 rsync 可用
  rsync -a "${src}/" "${PKG_DIR}/"
  echo "==> 已从目录复制到 ${PKG_DIR}"
}

extract_archive_to_pkg() {
  local archive="$1"
  [[ -f "${archive}" ]] || { echo "文件不存在: ${archive}" >&2; exit 1; }
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp}"' EXIT
  case "${archive}" in
    *.zip)
      unzip -q "${archive}" -d "${tmp}"
      ;;
    *.tar.gz|*.tgz)
      tar -xzf "${archive}" -C "${tmp}"
      ;;
    *.tar)
      tar -xf "${archive}" -C "${tmp}"
      ;;
    *)
      echo "不支持的归档后缀（请用 .zip / .tar.gz / .tgz / .tar）: ${archive}" >&2
      exit 1
      ;;
  esac
  local swift_path
  swift_path="$(find "${tmp}" -maxdepth 5 -name Package.swift 2>/dev/null | head -1 || true)"
  if [[ -z "${swift_path}" ]]; then
    echo "归档内未找到 Package.swift: ${archive}" >&2
    exit 1
  fi
  local root
  root="$(cd "$(dirname "${swift_path}")" && pwd)"
  mkdir -p "${HOST_DIR}/LocalPackages"
  rm -rf "${PKG_DIR}"
  mv "${root}" "${PKG_DIR}"
  echo "==> 已从归档解压到 ${PKG_DIR}"
  trap - EXIT
  rm -rf "${tmp}"
}

ensure_spm_source() {
  if [[ -f "${PKG_DIR}/Package.swift" ]]; then
    echo "==> 已存在 ${PKG_DIR}/Package.swift，跳过源码准备。"
    return 0
  fi
  if [[ -n "${FROM_DIR}" ]]; then
    copy_tree_into_pkg "$(cd "${FROM_DIR}" && pwd)"
    return 0
  fi
  if [[ -n "${FROM_ARCHIVE}" ]]; then
    extract_archive_to_pkg "$(cd "$(dirname "${FROM_ARCHIVE}")" && pwd)/$(basename "${FROM_ARCHIVE}")"
    return 0
  fi
  local git_url="${ONNXRUNTIME_SPM_GIT_URL:-${DEFAULT_SPM_GIT_URL}}"
  echo "==> git clone（若失败请改用 --from-dir / --from-archive 或设置 ONNXRUNTIME_SPM_GIT_URL 镜像）"
  echo "    URL: ${git_url}"
  mkdir -p "${HOST_DIR}/LocalPackages"
  rm -rf "${PKG_DIR}"
  if git clone --depth 1 --branch "${ORT_TAG}" "${git_url}" "${PKG_DIR}"; then
    echo "==> 已克隆到 ${PKG_DIR}"
  else
    echo "" >&2
    echo "git clone 失败（常见于无法访问 GitHub）。离线做法：" >&2
    echo "  1) 在有网电脑执行: git clone --depth 1 --branch ${ORT_TAG} ${DEFAULT_SPM_GIT_URL}" >&2
    echo "  2) 把整个 onnxruntime-swift-package-manager 目录拷到 U 盘" >&2
    echo "  3) 在本机执行:  cd \"${HOST_DIR}\" && ./bootstrap-onnx-local-package.sh --from-dir <该目录路径>" >&2
    exit 1
  fi
}

fetch_or_copy_zips() {
  mkdir -p "${VENDOR_DIR}"
  local pod_url="${ONNXRUNTIME_POD_ZIP_URL:-${DEFAULT_POD_ZIP_URL}}"
  local ext_url="${ONNXRUNTIME_EXT_ZIP_URL:-${DEFAULT_EXT_ZIP_URL}}"

  if [[ -n "${ONNXRUNTIME_ZIPS_DIR:-}" ]]; then
    local d="${ONNXRUNTIME_ZIPS_DIR}"
    if [[ -f "${d}/${ORT_ZIP_NAME}" && -f "${d}/${ORT_EXT_ZIP_NAME}" ]]; then
      cp -f "${d}/${ORT_ZIP_NAME}" "${d}/${ORT_EXT_ZIP_NAME}" "${VENDOR_DIR}/"
      echo "==> 已从 ONNXRUNTIME_ZIPS_DIR 复制二进制 zip 到 .vendor/"
      return 0
    fi
    echo "ONNXRUNTIME_ZIPS_DIR 已设置但缺少文件之一: ${ORT_ZIP_NAME} / ${ORT_EXT_ZIP_NAME}" >&2
    exit 1
  fi

  if [[ -f "${VENDOR_DIR}/${ORT_ZIP_NAME}" && -f "${VENDOR_DIR}/${ORT_EXT_ZIP_NAME}" ]]; then
    echo "==> .vendor 内 zip 已齐全，跳过下载。"
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1; then
    echo "需要 curl 下载 zip，或设置 ONNXRUNTIME_ZIPS_DIR 指向已下载的两个 zip" >&2
    exit 1
  fi

  if [[ ! -f "${VENDOR_DIR}/${ORT_ZIP_NAME}" ]]; then
    echo "==> 下载 ${ORT_ZIP_NAME} ← ${pod_url}"
    curl -fL --retry 3 --retry-delay 2 -o "${VENDOR_DIR}/${ORT_ZIP_NAME}.part" "${pod_url}" || {
      echo "下载失败。可手动下载后放到目录并: export ONNXRUNTIME_ZIPS_DIR=该目录 && $0 --with-zips" >&2
      exit 1
    }
    mv "${VENDOR_DIR}/${ORT_ZIP_NAME}.part" "${VENDOR_DIR}/${ORT_ZIP_NAME}"
  fi
  if [[ ! -f "${VENDOR_DIR}/${ORT_EXT_ZIP_NAME}" ]]; then
    echo "==> 下载 ${ORT_EXT_ZIP_NAME} ← ${ext_url}"
    curl -fL --retry 3 --retry-delay 2 -o "${VENDOR_DIR}/${ORT_EXT_ZIP_NAME}.part" "${ext_url}" || {
      echo "下载失败。可设置 ONNXRUNTIME_EXT_ZIP_URL 镜像或 ONNXRUNTIME_ZIPS_DIR 离线目录" >&2
      exit 1
    }
    mv "${VENDOR_DIR}/${ORT_EXT_ZIP_NAME}.part" "${VENDOR_DIR}/${ORT_EXT_ZIP_NAME}"
  fi
}

ensure_spm_source

if [[ "${DO_ZIPS}" -eq 1 ]]; then
  fetch_or_copy_zips
fi

echo "完成。构建前请确认 ${PKG_DIR}/Package.swift 存在；真机/模拟器见 run-simulator.sh / install-device.sh。"
