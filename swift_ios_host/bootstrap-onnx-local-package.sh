#!/usr/bin/env bash
# 一次性准备本地 OnnxRuntime Swift 包（不提交到 git，见 .gitignore）。
#
# 用法（在 swift_ios_host 目录下）：
#   ./bootstrap-onnx-local-package.sh              # 仅克隆微软仓库到 LocalPackages/（需能访问 GitHub）
#   ./bootstrap-onnx-local-package.sh --with-zips # 再下载 ORT 二进制 zip 到 .vendor/（需能访问 download.onnxruntime.ai）
#
# 说明：
# - 工程使用「本地路径」引用该包后，Xcode 不会每次从 GitHub 拉 **源码**；源码只在本目录更新时才会变。
# - 若未放 zip 且未设置 ORT_POD_*，微软 Package.swift 会在首次解析时从 download.onnxruntime.ai 拉二进制（只拉一次，之后有缓存）。
# - 若已放 zip，run-simulator.sh / install-device.sh 会自动 export ORT_POD_*，构建可完全离线（在已有 Derived/SPM 缓存的前提下）。

set -euo pipefail

ORT_TAG="1.24.2"
ORT_ZIP_URL="https://download.onnxruntime.ai/pod-archive-onnxruntime-c-1.24.2.zip"
ORT_EXT_ZIP_URL="https://download.onnxruntime.ai/pod-archive-onnxruntime-extensions-c-0.13.0.zip"
ORT_ZIP_NAME="pod-archive-onnxruntime-c-1.24.2.zip"
ORT_EXT_ZIP_NAME="pod-archive-onnxruntime-extensions-c-0.13.0.zip"

HOST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="${HOST_DIR}/LocalPackages/onnxruntime-swift-package-manager"
VENDOR_DIR="${PKG_DIR}/.vendor"

if [[ ! -f "${PKG_DIR}/Package.swift" ]]; then
  echo "==> 克隆 onnxruntime-swift-package-manager @ ${ORT_TAG} → ${PKG_DIR}"
  mkdir -p "${HOST_DIR}/LocalPackages"
  rm -rf "${PKG_DIR}"
  git clone --depth 1 --branch "${ORT_TAG}" \
    "https://github.com/microsoft/onnxruntime-swift-package-manager.git" \
    "${PKG_DIR}"
else
  echo "==> 已存在 ${PKG_DIR}/Package.swift，跳过克隆。"
fi

if [[ "${1:-}" == "--with-zips" ]]; then
  mkdir -p "${VENDOR_DIR}"
  if [[ ! -f "${VENDOR_DIR}/${ORT_ZIP_NAME}" ]]; then
    echo "==> 下载 ${ORT_ZIP_NAME}"
    curl -fL --retry 3 --retry-delay 2 -o "${VENDOR_DIR}/${ORT_ZIP_NAME}.part" "${ORT_ZIP_URL}"
    mv "${VENDOR_DIR}/${ORT_ZIP_NAME}.part" "${VENDOR_DIR}/${ORT_ZIP_NAME}"
  else
    echo "==> 已存在 ${VENDOR_DIR}/${ORT_ZIP_NAME}"
  fi
  if [[ ! -f "${VENDOR_DIR}/${ORT_EXT_ZIP_NAME}" ]]; then
    echo "==> 下载 ${ORT_EXT_ZIP_NAME}"
    curl -fL --retry 3 --retry-delay 2 -o "${VENDOR_DIR}/${ORT_EXT_ZIP_NAME}.part" "${ORT_EXT_ZIP_URL}"
    mv "${VENDOR_DIR}/${ORT_EXT_ZIP_NAME}.part" "${VENDOR_DIR}/${ORT_EXT_ZIP_NAME}"
  else
    echo "==> 已存在 ${VENDOR_DIR}/${ORT_EXT_ZIP_NAME}"
  fi
fi

echo "完成。请在 Xcode 或 ./run-simulator.sh / ./install-device.sh 中验证构建。"
