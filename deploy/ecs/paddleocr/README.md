# 阿里云 ECS 上的 PaddleOCR（歌谱图片 OCR）

## 外网 HTTPS（Nginx 反代，已配）

假设域名与仓库 `guitar-server.conf` 一致，外网通过 **443** 访问（路径带 **`/paddleocr/`** 前缀）：

- 健康检查：`https://wanghanai.xyz/paddleocr/health`
- OCR 上传：`POST https://wanghanai.xyz/paddleocr/ocr`（`multipart/form-data` 字段名 `file`）

**只要和弦+歌词（后处理，过滤简谱/页眉等）**：

- `POST .../ocr?content=song`（与 `file` 同发）
- 返回：`chord_lines`（OCR 能认出的英文和弦行）、`lyric_lines`（高概率中文句）、`chord_tokens_flat`、各 `dropped_*_sample` 便于调参
- 需要原始行时加：`&include_raw=true`

示例：

```bash
curl -sS -X POST "https://wanghanai.xyz/paddleocr/ocr?content=song" -F "file=@page.png;type=image/png" | python3 -m json.tool
```

Nginx 将 `/paddleocr/` 剥掉后转发到本机 `127.0.0.1:18081`（`proxy_pass` 配置见 `deploy/ecs/nginx/guitar-server.conf`）。

**关于和弦**：谱顶英文和弦常因字号小或与六线贴在一起而**进不了 OCR 行**；`content=song` 只从**已有**文本里再筛。要提高和弦召回，可尝试更高分辨率、裁切**上半条**再识别，或乐谱专用模型（后续可迭代）。

## 一键：在本机同步并完成安装（推荐）

在**你本机能 SSH 进 ECS 的终端**里，进入本仓库后执行（私钥路径按实际修改）：

```bash
cd /path/to/guitar-ai-coach
ECS_KEY="$HOME/Documents/guitar-ai-coach/my-ecs-key2.pem" ./deploy/ecs/paddleocr/push-and-setup.sh
```

脚本会：`rsync` 本目录 → `~/guitar-ai-coach/deploy/ecs/paddleocr/`、安装 **Paddle 2.6.2 + PaddleOCR 2.7**、做一次 OCR 冒烟、`nohup` 启动 `127.0.0.1:18081`，并 `curl /health`。

若 Cursor/CI 环境无法 SSH（对端 reset），用上述本机命令即可接续完成。

## 环境约定

- **Conda 环境名**：`paddleocr`（`~/miniconda3`）
- **推荐版本**：PaddlePaddle `2.6.2`（CPU）+ PaddleOCR `2.7.0.3`（经典 API）  
  若使用 Paddle 3.x + PaddleOCR 3.x 默认的 PP-OCRv5 管线，在部分 **CPU/Alibaba Cloud Linux** 上可能触发 oneDNN/PIR 相关 `NotImplementedError`，因此线上采用 **2.6 + 2.7** 组合更稳。
- **内存**：OCR 首次加载模型时内存占用明显；当前部分 ECS 为 **~2G RAM**，首启可能较慢或 OOM。若常失败，请在控制台 **扩容内存** 或经管理员 **增加 swap**（需 root）。
- **NumPy**：需 **1.x**（`numpy>=1.24,<2`）。若曾误升 **NumPy 2.x**，会出现 `cv2` / `numpy.core.multiarray` 导入错误，需按 `requirements-paddleocr.txt` 重新安装并 `pip install "opencv-python-headless>=4.6" --force-reinstall`。

## 安装/修复依赖（在 ECS 上执行）

```bash
source "$HOME/miniconda3/etc/profile.d/conda.sh"
conda activate paddleocr

python -m pip install "paddlepaddle==2.6.2" -i https://www.paddlepaddle.org.cn/packages/stable/cpu/
python -m pip install -r requirements-paddleocr.txt -i https://pypi.tuna.tsinghua.edu.cn/simple
```

（将本目录同步到 `~/guitar-ai-coach/deploy/ecs/paddleocr/` 后，在上列路径中执行。）

## 启动服务

仅本机回环，默认 **18081**（与 `guitar-ai-coach-backend` 的 18080 区分）：

```bash
cd ~/guitar-ai-coach/deploy/ecs/paddleocr
./run.sh
# 或：PADDLEOCR_PORT=18081 PADDLEOCR_BIND=127.0.0.1 ./run.sh
```

后台保持运行示例：

```bash
nohup ./run.sh >> ~/paddleocr-serve.log 2>&1 &
```

本机自测（需先在服务器上准备一张小图或传文件）：

```bash
curl -sS http://127.0.0.1:18081/health
# 上传（multipart）
curl -sS -X POST http://127.0.0.1:18081/ocr -F "file=@/path/to/sheet.png"
```

## 与「和弦/歌词」的关系

- PaddleOCR 输出的是 **图像中的文字行**（`lines` 与 `full_text`），歌词与可印刷和弦符号会进入识别结果。
- **和弦与歌词的语义分段、和弦根音解析** 仍需应用层规则或乐谱专用模型，本服务不单独做音乐理论推理。

## SSH 与路径

- 公网 IP、用户、本机私钥等见仓库发布运维约定与 `release-ops-workflow` skill。私钥**勿提交 Git**。
