# 本机 ONNX Swift 包（不提交到 git）

`onnxruntime-swift-package-manager` 由 `../bootstrap-onnx-local-package.sh` 放入本目录，**体积大、不进入版本库**（见 `.gitignore`）。

- **保留下载结果**：`bootstrap` 在已存在 `onnxruntime-swift-package-manager/Package.swift` 时会**直接跳过、不会删目录**；重复执行时只会补全缺失内容（如 `--with-zips` 且 zip 尚未下载）。只有加上 **`--force`** 才会清掉后重装。
- **别被 git 清掉**：`git clean -fdx` 会删除 **已忽略、未提交** 的文件/目录，整段 `LocalPackages/onnxruntime-swift-package-manager/` 可能被删掉。清理仓库时优先用 `git clean -fd`（不带 `x`），或显式排除本目录。

新 clone / 新 worktree 下若该目录不存在，需在本机**再跑一遍** bootstrap，或从其它机器/备份拷贝同一路径整目录即可。
