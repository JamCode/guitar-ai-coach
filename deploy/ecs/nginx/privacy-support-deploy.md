# 隐私政策与技术支持静态页部署（阿里云 NGINX）

目标页面：

- `https://你的域名/privacy.html`
- `https://你的域名/support.html`

## 1) 静态文件放置路径

建议使用（与当前站点根一致）：

- 服务器目录：`/home/wanghan/guitar-ai-coach/site`
- 页面文件：
  - `/home/wanghan/guitar-ai-coach/site/privacy.html`
  - `/home/wanghan/guitar-ai-coach/site/support.html`

本仓库对应源文件：

- `site/privacy.html`
- `site/support.html`

## 2) NGINX 配置示例（HTTPS 域名）

将以下 server 块纳入 NGINX 配置（可并入现有 `deploy/ecs/nginx/guitar-server.conf` 的 443 server）：

```nginx
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name 你的域名;

    ssl_certificate     /path/to/fullchain.pem;
    ssl_certificate_key /path/to/privkey.pem;

    root /home/wanghan/guitar-ai-coach/site;
    index index.html;

    location = /privacy.html {
        try_files /privacy.html =404;
        add_header Cache-Control "no-cache, no-store, must-revalidate";
    }

    location = /support.html {
        try_files /support.html =404;
        add_header Cache-Control "no-cache, no-store, must-revalidate";
    }

    location / {
        try_files $uri $uri/ /index.html;
    }
}
```

> 当前项目已有 HTTPS 站点配置，可直接复用证书路径与 `root /home/wanghan/guitar-ai-coach/site;`。

## 3) 部署步骤

1. 同步页面到 ECS：

```bash
rsync -avz -e "ssh -i $ECS_KEY -o StrictHostKeyChecking=accept-new" \
  site/privacy.html site/support.html \
  ${ECS_USER}@${ECS_HOST}:/home/wanghan/guitar-ai-coach/site/
```

2. （如需）同步 NGINX 配置并测试：

```bash
rsync -avz -e "ssh -i $ECS_KEY -o StrictHostKeyChecking=accept-new" \
  deploy/ecs/nginx/guitar-server.conf \
  ${ECS_USER}@${ECS_HOST}:/home/wanghan/guitar-ai-coach/deploy/ecs/nginx/guitar-server.conf
```

3. 在 ECS 重载 NGINX：

```bash
ssh -i "$ECS_KEY" ${ECS_USER}@${ECS_HOST} \
  "sudo nginx -t && sudo systemctl reload nginx"
```

## 4) 验证命令

```bash
curl -I https://你的域名/privacy.html
curl -I https://你的域名/support.html
curl -sS https://你的域名/privacy.html | head -n 5
curl -sS https://你的域名/support.html | head -n 5
```

预期：HTTP `200`，内容分别为隐私政策与技术支持页面。

