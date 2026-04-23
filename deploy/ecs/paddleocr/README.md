# 阿里云 ECS 上的 PaddleOCR（歌谱图片 OCR）

## 环境约定

- **Conda 环境名**：`paddleocr`（`~/miniconda3`）
- **推荐版本**：PaddlePaddle `2.6.2`（CPU）+ PaddleOCR `2.7.0.3`（经典 API）  
  若使用 Paddle 3.x + PaddleOCR 3.x 默认的 PP-OCRv5 管线，在部分 **CPU/Alibaba Cloud Linux** 上可能触发 oneDNN/PIR 相关 `NotImplementedError`，因此线上采用 **2.6 + 2.7** 组合更稳。
- **内存**：OCR 首次加载模型时内存占用明显；当前部分 ECS 为 **~2G RAM**，首启可能较慢或 OOM。若常失败，请在控制台 **扩容内存** 或经管理员 **增加 swap**（需 root）。

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
