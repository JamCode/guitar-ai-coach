# Local Swift packages

扒歌和弦识别已改为**仅调用远端 ONNX 服务**，本工程不再链接 `onnxruntime` Swift 包。

若你仍在本机保留历史目录 `LocalPackages/onnxruntime-swift-package-manager/`，可手动删除；`.gitignore` 中条目可保留无害。
