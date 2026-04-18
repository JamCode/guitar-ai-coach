# ECS 部署说明（Guitar AI Coach）

本文记录**当前在用**的云服务器约定与前后端发布步骤，便于本机或自动化重复执行。**不要**在此文件或 Git 中写入 SSH 密码、`backend.env` 里的 API Key，或私钥内容。

## 服务器与环境

| 项 | 值 |
| --- | --- |
| ECS 公网 IP | `47.110.78.65` |
| SSH 用户（日常） | `wanghan` |
| 项目在服务器上的根路径 | `/home/wanghan/guitar-ai-coach` |
| **Nginx 静态根目录（`wanghan` 可写，发布无需 root）** | `/home/wanghan/guitar-ai-coach/site` |
| 后端代码目录 | `/home/wanghan/guitar-ai-coach/backend/code` |
| 后端环境变量文件 | `/home/wanghan/guitar-ai-coach/deploy/ecs/backend.env` |
| systemd 服务名 | `guitar-ai-coach-backend` |
| 后端进程监听（本机回环） | `127.0.0.1:18080` |
| **日常可改的站点 Nginx（`wanghan` 可写，无需 sudo）** | `deploy/ecs/nginx/guitar-server.conf` → 服务器 `${ECS_PATH}/deploy/ecs/nginx/guitar-server.conf`；改完 **`rsync` + `sudo nginx -t` + `reload`**（后两项已 NOPASSWD） |
| 仓库内 Nginx **主配置**副本 | `deploy/nginx-ecs/nginx/nginx.conf`（内含 `include` 指向上行家目录文件）。默认覆盖 `/etc/nginx/nginx.conf` 需 root；若已按下文 **将 `/etc/nginx` 交 `wanghan`**，则可 **`rsync` 直传** `/etc/nginx/nginx.conf`，无需 `sudo cp` |
| **`wanghan` 的 sudo（当前 ECS）** | 已配置 **NOPASSWD**（仅限下文 sudoers 示例中的 `systemctl restart guitar-ai-coach-backend`、`systemctl reload nginx`、`nginx -t`），**脚本/CI 可非交互执行** |

SSH 使用**密钥登录**（登录不输密码）。**sudo** 与登录无关：当前服务器上上述命令已 **NOPASSWD**，无需再输 `wanghan` 登录密码。私钥放在本机安全路径；**不要将 `.pem` 提交到 Git**。

---

## 本机环境变量（便于复制执行）

在本地终端先设置（把 `ECS_KEY` 改成你的私钥绝对路径）：

```bash
export ECS_HOST=47.110.78.65
export ECS_USER=wanghan
export ECS_KEY="/path/to/your-ecs-private-key.pem"
export ECS_PATH=/home/wanghan/guitar-ai-coach
export ECS_SITE="${ECS_PATH}/site"
chmod 600 "$ECS_KEY"
```

以下命令默认在**本机仓库根目录** `guitar-ai-coach/` 下执行。

---

## 首次：站点目录 + Nginx 指向（在 ECS 上只需做一次，需 root）

目标：**Nginx `root` 指向 `wanghan` 拥有且可写的目录**，日常发布只 rsync，**不必再 SSH root**。

1. **建目录、属主、权限（nginx 进程用户需能沿路径读文件，一般为 `nginx`）**

```bash
sudo mkdir -p /home/wanghan/guitar-ai-coach/site
sudo chown -R wanghan:wanghan /home/wanghan/guitar-ai-coach/site
# 若家目录为 700，nginx 无法进入，需放行「沿路径进入」（任选其一，按你们安全策略收紧）：
sudo chmod 711 /home/wanghan
sudo chmod 755 /home/wanghan/guitar-ai-coach
sudo chmod 755 /home/wanghan/guitar-ai-coach/site
```

2. **（可选）把当前线上静态文件迁到新目录**，避免切换后空白页：

```bash
sudo rsync -av /usr/share/nginx/html/ /home/wanghan/guitar-ai-coach/site/
sudo chown -R wanghan:wanghan /home/wanghan/guitar-ai-coach/site
```

3. **更新 Nginx 主配置（通常只需做一次）**：主配置在 `/etc/nginx/nginx.conf`，其中用 **`include`** 加载家目录下的站点块，这样以后改路由/反代只动 `wanghan` 可写路径，**不必再 `sudo` 写 `/etc`**：

   - 先把仓库里的 **`deploy/ecs/nginx/guitar-server.conf`** rsync 到服务器  
     `${ECS_PATH}/deploy/ecs/nginx/guitar-server.conf`（与下条主配置里的路径一致）。
   - 再将仓库内 **`deploy/nginx-ecs/nginx/nginx.conf`** 覆盖到服务器 **`/etc/nginx/nginx.conf`**，然后：

```bash
sudo nginx -t && sudo systemctl reload nginx
```

   之后若只改站点逻辑（`try_files`、`location /api/` 等），只需 **rsync `guitar-server.conf`**，再执行（免密）：

```bash
sudo nginx -t && sudo systemctl reload nginx
```

若出现 **403**，多半是 `nginx` 用户对 `/home/wanghan` 没有执行权限，回到第 1 步检查 `chmod 711 /home/wanghan` 或改用 ACL：`setfacl -m u:nginx:rx /home/wanghan`（及对下级目录递归，仅开放到 `site` 路径所需）。**include 的家目录路径**也需对 `nginx` 用户可执行进入（一般 `chmod 755` 到 `guitar-ai-coach` 及下级至 `deploy/ecs/nginx/` 即可）。

4. **（可选）用 root 把 `/etc/nginx` 交给 `wanghan` 直接改**  
   若你希望**本机 `rsync` 即可覆盖** `nginx.conf`（以及 `conf.d` 等），不必再 `sudo cp`，可在 ECS 上 **以 root** 执行：

```bash
chown -R wanghan:wanghan /etc/nginx
find /etc/nginx -type f -exec chmod 644 {} \;
find /etc/nginx -type d -exec chmod 755 {} \;
```

   之后在本机可直接：

```bash
rsync -avz -e "ssh -i $ECS_KEY -o StrictHostKeyChecking=accept-new" \
  deploy/nginx-ecs/nginx/nginx.conf "${ECS_USER}@${ECS_HOST}:/etc/nginx/nginx.conf"
ssh -i "$ECS_KEY" -o StrictHostKeyChecking=accept-new "${ECS_USER}@${ECS_HOST}" \
  "sudo nginx -t && sudo systemctl reload nginx"
```

   **注意**：`wanghan` 将能修改**整目录**下的 Nginx 配置（安全面大于只改家目录里的 `guitar-server.conf`）。**`dnf` / `yum upgrade nginx`** 后包管理器可能把部分文件属主改回 `root`，若 `rsync` 报权限错误，再执行一次上面的 `chown` / `chmod` 即可。

---

## HTTPS（Let's Encrypt）

仓库内 **`deploy/ecs/nginx/guitar-server.conf`** 已按 **Certbot 默认证书路径**（`/etc/letsencrypt/live/wanghanai.xyz/`）写好 **443** 与 **80→HTTPS 跳转**（**80 上仍保留** `/.well-known/acme-challenge/`，便于签发与续期）。

**顺序（不要颠倒）**：当前线上若是「仅 HTTP、可访问 ACME 路径」的旧配置，先在 ECS 上 **申请证书**，再 **rsync 本文件并 reload**。若尚未有证书就 rsync 含 `ssl_certificate` 的新配置，`nginx -t` 会因找不到证书文件而失败。

1. **安全组**：在阿里云 ECS 安全组中为公网入方向放行 **TCP 443**（80 已有则保持）。

2. **在 ECS 上安装 Certbot**（择一，按系统调整；需 `sudo`）：

   ```bash
   # Alibaba Cloud Linux 3 / CentOS Stream 等（dnf）
   sudo dnf install -y certbot

   # 或 CentOS 7：先启用 EPEL 再安装 certbot（以官方文档为准）
   # sudo yum install -y epel-release && sudo yum install -y certbot
   ```

3. **用 Webroot 申请证书**（与 Nginx 中 `root` 一致；把邮箱改成你的）：

   ```bash
   sudo certbot certonly --webroot \
     -w /home/wanghan/guitar-ai-coach/site \
     -d wanghanai.xyz -d www.wanghanai.xyz \
     --email you@example.com --agree-tos --non-interactive
   ```

4. **同步站点配置并重载 Nginx**（在本机仓库根目录，已设置 `ECS_*` 环境变量时）：

   ```bash
   rsync -avz -e "ssh -i $ECS_KEY -o StrictHostKeyChecking=accept-new" \
     deploy/ecs/nginx/guitar-server.conf "${ECS_USER}@${ECS_HOST}:${ECS_PATH}/deploy/ecs/nginx/guitar-server.conf"
   ssh -i "$ECS_KEY" -o StrictHostKeyChecking=accept-new "${ECS_USER}@${ECS_HOST}" \
     "sudo nginx -t && sudo systemctl reload nginx"
   ```

5. **续期成功后重载 Nginx**（发行版自带的 `certbot renew` 定时任务通常**不会** reload nginx；在 ECS 上执行一次即可）：

   ```bash
   sudo tee /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh <<'EOF'
#!/bin/sh
systemctl reload nginx
EOF
   sudo chmod +x /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
   ```

   可用 `sudo certbot renew --dry-run` 自检续期；通过后下次自动续期会执行上述 hook。

验证：浏览器访问 `https://wanghanai.xyz/` ，或用 `curl -I https://wanghanai.xyz/` 应返回 **200** 且证书链完整。

---

## 部署后端

### 1. 同步 Python 代码

```bash
rsync -avz -e "ssh -i $ECS_KEY -o StrictHostKeyChecking=accept-new" \
  backend/code/ "${ECS_USER}@${ECS_HOST}:${ECS_PATH}/backend/code/"
```

和弦 explain 的 MySQL 缓存依赖表 **`chord_explain_cache`**，DDL 在 **`backend/database/ddl/chord_explain_cache.sql`**。启用 `MYSQL_*` 前须在数据库里**手工执行**该 SQL（后端不会在代码里建表）。应用连接请使用 **`guitar_app@localhost`**（勿用 root），并在库中对该表授权：**`backend/database/ddl/grant_chord_explain_cache_guitar_app.sql`**（若已对 `guitar_ai_coach.*` 授予 `ALL`，该脚本可省略，仅作权限说明）。

题库训练（Quiz）新增三张表 DDL：**`backend/database/ddl/quiz_training_tables.sql`**，授权脚本：**`backend/database/ddl/grant_quiz_training_tables_guitar_app.sql`**。执行完 DDL 后，可调用：

```bash
curl -X POST "http://${ECS_HOST}/api/quiz/admin/init-seed" \
  -H "Content-Type: application/json" \
  -d '{"seed_file":"/home/wanghan/guitar-ai-coach/backend/database/quiz_seed_100_v2.json","status":"active"}'
```

将 100 题种子导入 `quiz_question`（需先把种子 JSON 同步到服务器该路径）。

练耳训练（Ear）新增五张表 DDL：**`backend/database/ddl/ear_training_tables.sql`**，授权脚本：**`backend/database/ddl/grant_ear_training_tables_guitar_app.sql`**。执行完 DDL 后，可调用：

```bash
curl -X POST "http://${ECS_HOST}/api/ear/admin/init-seed" \
  -H "Content-Type: application/json" \
  -d '{"seed_file":"/home/wanghan/guitar-ai-coach/requirements/练耳题库-一期种子.json","status":"active"}'
```

将一期练耳种子导入 `ear_question`。

找歌和弦（第 4 tab）新增四张表 DDL：**`backend/database/ddl/song_chords_tables.sql`**，授权脚本：**`backend/database/ddl/grant_song_chords_tables_guitar_app.sql`**。执行后端前请先执行这两份 SQL，再用 `curl http://${ECS_HOST}/api/song-chords/health` 自检（应返回 `ok: true`）。

原则：**历史基线**在 `backend/database/ddl/`（首次建库顺序见该目录 `README.md`）；**本期起新增 schema** 放在 **`backend/database/flyway/sql/V*__*.sql`**，发版时用 **Flyway** `migrate` 执行（见 `backend/database/flyway/README.md`）。运行时代码不自动建表。

可将 DDL 目录同步到服务器便于运维：

```bash
rsync -avz -e "ssh -i $ECS_KEY -o StrictHostKeyChecking=accept-new" \
  backend/database/ "${ECS_USER}@${ECS_HOST}:${ECS_PATH}/backend/database/"
```

### 2.（可选）同步环境变量

本地若改了 `deploy/ecs/backend.env`：

```bash
rsync -avz -e "ssh -i $ECS_KEY -o StrictHostKeyChecking=accept-new" \
  deploy/ecs/backend.env "${ECS_USER}@${ECS_HOST}:${ECS_PATH}/deploy/ecs/backend.env"
```

**注意**：`backend.env` 含 `DASHSCOPE_API_KEY` 等敏感信息，勿推送到公开仓库。

### 3. 重启后端服务

（依赖 `wanghan` 的 **NOPASSWD** `systemctl restart guitar-ai-coach-backend`，见上文环境表。）

```bash
ssh -i "$ECS_KEY" -o StrictHostKeyChecking=accept-new \
  "${ECS_USER}@${ECS_HOST}" \
  "sudo systemctl restart guitar-ai-coach-backend && sudo systemctl is-active guitar-ai-coach-backend"
```

### 4. 服务器本机自检（可选）

```bash
ssh -i "$ECS_KEY" "${ECS_USER}@${ECS_HOST}" \
  "curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:18080/styles"
```

应返回 `200`（且 `backend.env` 已配置模型 Key 时，生成类接口才正常）。

---

## 部署前端

### 1. 本地构建

```bash
cd frontend
npm ci
npm run build
cd ..
```

依赖已齐全时可省略 `npm ci`，直接 `npm run build`。

### 2. 发布到 Nginx 静态根（`wanghan` 直接写入，无需 root）

先完成上文「首次：站点目录 + Nginx 指向」。`ECS_SITE` 与 `ECS_PATH` 已在环境变量中定义。

```bash
rsync -avz -e "ssh -i $ECS_KEY -o StrictHostKeyChecking=accept-new" --delete \
  frontend/dist/ "${ECS_USER}@${ECS_HOST}:${ECS_SITE}/"

# 若站点下存在证书探针目录 .well-known（通常由 root/certbot 管理），
# 建议排除，避免 --delete 因权限失败中断：
rsync -avz -e "ssh -i $ECS_KEY -o StrictHostKeyChecking=accept-new" --delete \
  --exclude ".well-known/**" \
  frontend/dist/ "${ECS_USER}@${ECS_HOST}:${ECS_SITE}/"
```

仅更新静态资源时，一般**不必** `reload nginx`。

若改了 **站点** Nginx（`deploy/ecs/nginx/guitar-server.conf`），rsync 到 `${ECS_PATH}/deploy/ecs/nginx/` 后执行（**无需**再写 `/etc/nginx`，`wanghan` 对家目录文件即可）：

```bash
rsync -avz -e "ssh -i $ECS_KEY -o StrictHostKeyChecking=accept-new" \
  deploy/ecs/nginx/guitar-server.conf "${ECS_USER}@${ECS_HOST}:${ECS_PATH}/deploy/ecs/nginx/"
ssh -i "$ECS_KEY" -o StrictHostKeyChecking=accept-new "${ECS_USER}@${ECS_HOST}" \
  "sudo nginx -t && sudo systemctl reload nginx"
```

若改了 **主配置**（`deploy/nginx-ecs/nginx/nginx.conf`，例如改 `include` 路径），才需要再 `sudo` 覆盖 `/etc/nginx/nginx.conf` 后同样执行 `nginx -t` 与 `reload`。

（`nginx -t` / `reload` 需 `sudo`；当前 ECS 上已对 `wanghan` **NOPASSWD**，无需交互密码。）

---

## 公网冒烟测试（本机）

```bash
curl -sS -o /dev/null -w "GET / -> %{http_code}\n" "http://${ECS_HOST}/"
curl -sS -o /dev/null -w "GET /dictionary -> %{http_code}\n" "http://${ECS_HOST}/dictionary"
curl -sS -o /dev/null -w "GET /api/styles -> %{http_code}\n" "http://${ECS_HOST}/api/styles"
```

若直接访问 `/dictionary` 返回 **404** 而非 `index.html`，说明 Nginx 未配置 SPA 回退，请在 **`deploy/ecs/nginx/guitar-server.conf`** 的 `location /` 中保留 `try_files $uri $uri/ /index.html;`（亦可见 `deploy/ecs/nginx-site.example.conf`）。

---

## 首次安装 systemd 单元（服务器上只需做一次）

将仓库内 `guitar-ai-coach-backend.service` 安装到 systemd（路径以服务器为准）：

```bash
sudo cp /home/wanghan/guitar-ai-coach/deploy/ecs/guitar-ai-coach-backend.service \
  /etc/systemd/system/guitar-ai-coach-backend.service
sudo systemctl daemon-reload
sudo systemctl enable --now guitar-ai-coach-backend
```

确保 `backend.env` 已放到 `EnvironmentFile` 指向的路径，且 `DASHSCOPE_API_KEY` 等已填写。

---

## `wanghan` 的 sudo 免密（当前 ECS 已启用；新机器可参考）

与 **SSH 密钥登录** 不同：这里指 **`sudo` 指定命令不再问密码**，便于本地脚本、Cursor 等非 TTY 环境部署。

**当前 ECS 已按下列示例配置。** 若换新实例或权限被改，在服务器上以 **root** 执行：

```bash
visudo -f /etc/sudoers.d/wanghan-deploy
```

当前 ECS 上实际文件与下列一致（路径以 `readlink -f $(command -v systemctl)` 为准，常见为 `/usr/bin/systemctl`）。含 **`!requiretty`**，便于非交互 SSH 里执行 `sudo`。

```sudoers
# guitar-ai-coach: wanghan 部署脚本非交互 sudo（勿扩大命令面）
Defaults:wanghan !requiretty
wanghan ALL=(root) NOPASSWD: /usr/bin/systemctl restart guitar-ai-coach-backend
wanghan ALL=(root) NOPASSWD: /usr/bin/systemctl is-active guitar-ai-coach-backend
wanghan ALL=(root) NOPASSWD: /usr/bin/systemctl reload nginx
wanghan ALL=(root) NOPASSWD: /usr/sbin/nginx -t
```

保存后：

```bash
chmod 440 /etc/sudoers.d/wanghan-deploy
visudo -c -f /etc/sudoers.d/wanghan-deploy
visudo -c
```

用 `wanghan` 验证（**不要**用 `sudo -n true`，`true` 不在白名单会提示要密码）：

```bash
sudo -n systemctl is-active guitar-ai-coach-backend && echo "NOPASSWD ok"
sudo -n nginx -t
```

---

## 功能迭代后：发布与自测（建议每次照做）

本地改完代码后，同步到 ECS 并做最小自测，避免「只改仓库未上线」：

1. `cd frontend && npm run build`
2. `rsync` **`backend/code/`**（及有变更时的 **`backend/database/`**）到 `${ECS_PATH}`
3. `rsync --delete` **`frontend/dist/`** 到 **`${ECS_PATH}/site/`**（`wanghan` 无需 root）
4. 若改了 **`deploy/ecs/nginx/guitar-server.conf`**：`rsync` 到 `${ECS_PATH}/deploy/ecs/nginx/`，再 **`sudo nginx -t && sudo systemctl reload nginx`**（NOPASSWD）
5. **`sudo systemctl restart guitar-ai-coach-backend`**（`wanghan` 已 **NOPASSWD**，可非交互）
   - 若执行授权 SQL（`grant_*.sql`）报 `GRANT command denied`，说明当前账号无授权权限；
     这是正常权限边界，改为 DBA/root 一次性执行授权即可，日常发布可跳过该步骤。
6. **自测**（本机）：
   - `curl -sS -o /dev/null -w '%{http_code}\n' http://${ECS_HOST}/`
   - `curl -sS -o /dev/null -w '%{http_code}\n' http://${ECS_HOST}/api/styles`
   - `curl -sS -X POST http://${ECS_HOST}/api/chords/explain -H 'Content-Type: application/json' -d '{"symbol":"C","key":"C","level":"初级"}'` 应返回 **200** 且 JSON 含 `explain.frets`（长度 6）

---

## GitHub Actions 自动部署（后端 Python + Flyway）

仓库工作流：`.github/workflows/ecs-backend-deploy.yml`。

- **触发**：向 `main` 或 `tiaoyinqi` **push**，且变更落在 `backend/code/**` 或 `backend/database/flyway/sql/**`（或 `flyway.conf`）时；也可在 Actions 里 **手动 Run workflow**（会尽量执行 Flyway + 同步后端并重启，见工作流内注释）。
- **Python 有变更**：`rsync backend/code/` 到 ECS，再 `sudo systemctl restart guitar-ai-coach-backend`，并对 `http://127.0.0.1:18080/styles` 做冒烟。
- **Flyway 有变更**：在 GitHub Runner 上经 **SSH 隧道**连接 ECS 可达的 MySQL，执行 `flyway validate` / `flyway migrate`（不对外开端口）；随后将 `backend/database/flyway/` rsync 到服务器便于运维对照。

需在 GitHub 仓库配置 **Secrets / Variables**（名称与说明见工作流文件头部注释）。**勿**将 SSH 私钥或数据库密码写入仓库。

---

## 相关文件

| 文件 | 说明 |
| --- | --- |
| `guitar-ai-coach-backend.service` | systemd 单元模板 |
| `backend.env.example` | 环境变量示例（复制为 `backend.env` 后填真实值） |
| `nginx/guitar-server.conf` | **线上实际编辑的** `server {}`（家目录 rsync，含 SPA `try_files` 与 `/api/` 反代） |
| `nginx-site.example.conf` | 独立 `server` 片段示例（与 `guitar-server.conf` 对照用） |
| `../nginx-ecs/nginx/nginx.conf` | Nginx **主配置**副本（仅 `include` 指向上行；覆盖 `/etc/nginx/nginx.conf` 需 root **一次**） |
