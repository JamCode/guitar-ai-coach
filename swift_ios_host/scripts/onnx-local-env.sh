#!/usr/bin/env bash
# 由 run-simulator.sh / install-device.sh 在设置好 HOST_DIR 后 source。
# 若本地包内已有 .vendor 下的 ORT zip，则设置 ORT_POD_*（相对 Package.swift 所在目录），避免再走 download.onnxruntime.ai。

: "${HOST_DIR:?HOST_DIR must be set before sourcing onnx-local-env.sh}"

PKG_DIR="${HOST_DIR}/LocalPackages/onnxruntime-swift-package-manager"
ORT_ZIP="${PKG_DIR}/.vendor/pod-archive-onnxruntime-c-1.24.2.zip"
ORT_EXT_ZIP="${PKG_DIR}/.vendor/pod-archive-onnxruntime-extensions-c-0.13.0.zip"

if [[ -f "${ORT_ZIP}" && -f "${ORT_EXT_ZIP}" ]]; then
  export ORT_POD_LOCAL_PATH=".vendor/pod-archive-onnxruntime-c-1.24.2.zip"
  export ORT_EXTENSIONS_POD_LOCAL_PATH=".vendor/pod-archive-onnxruntime-extensions-c-0.13.0.zip"
  echo "==> OnnxRuntime：使用本地二进制 zip（ORT_POD_LOCAL_PATH 已设置）"
else
  unset ORT_POD_LOCAL_PATH ORT_EXTENSIONS_POD_LOCAL_PATH 2>/dev/null || true
  echo "==> OnnxRuntime：未检测到 .vendor 内 zip，将使用 Package.swift 默认 URL（首次需联网下载二进制）"
fi
