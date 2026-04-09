# Deploy 目录

| 路径 | 用途 |
| --- | --- |
| [`ecs/`](ecs/) | 后端 **systemd**、**backend.env 模板**、**ECS 服务器信息与前后端部署步骤**（[`ecs/README.md`](ecs/README.md)） |
| [`nginx-ecs/nginx/`](nginx-ecs/nginx/) | 从 ECS 同步的 **Nginx 主配置** 副本（含 `/api/` → `127.0.0.1:18080`） |
| [`../backend/database/ddl/`](../backend/database/ddl/) | **历史 MySQL 基线 DDL**（首次建库顺序见该目录 `README.md`） |
| [`../backend/database/flyway/`](../backend/database/flyway/) | **版本化迁移**（`sql/V*__*.sql` + Flyway CLI，见 `README.md`） |

发布到云服务器的完整命令与 IP、路径约定，见 **[`ecs/README.md`](ecs/README.md)**。
