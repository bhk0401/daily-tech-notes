# Platform Engineering：Internal Developer Platform (IDP) 与 Backstage 实战

## 背景与目标

随着云原生技术的普及，微服务架构成为主流，但随之而来的是开发复杂度的指数级增长。开发者需要面对 Kubernetes、服务网格、CI/CD 流水线、监控告警、密钥管理等一系列基础设施问题。Platform Engineering（平台工程）应运而生，其核心目标是**通过构建 Internal Developer Platform (IDP) 来降低开发者的认知负担，提升交付效率**。

根据 Gartner 的预测，到 2026 年，80% 的软件工程组织将建立平台工程团队。IDP 不是简单的工具堆砌，而是一套**以开发者体验为中心**的抽象层，将底层基础设施的复杂性封装成自助服务（Self-Service）能力。

本文的目标是：
1. 解析 Platform Engineering 的核心理念与 IDP 的架构设计
2. 深入讲解 Backstage 作为开源 IDP 框架的核心组件
3. 提供一个可运行的 Backstage 最小化部署示例
4. 分享生产环境中的常见陷阱与排查思路
5. 给出 IDP 落地的 CheckList，帮助团队评估与规划

## 核心概念

### Platform Engineering vs DevOps

Platform Engineering 不是 DevOps 的替代，而是其演进。DevOps 强调开发与运维的协作，而 Platform Engineering 更进一步，**将运维能力产品化**，由专门的平台团队构建和维护 IDP，开发者作为"用户"消费这些能力。

| 维度 | DevOps | Platform Engineering |
|------|--------|---------------------|
| 目标 | 打破部门墙 | 提供自助服务平台 |
| 交付物 | 流程与文化 | 平台产品 + API |
| 度量 | 部署频率、MTTR | 开发者满意度、平台采用率 |
| 团队 | 跨职能协作 | 平台团队 + 应用团队 |

### IDP 的核心能力

一个成熟的 IDP 应提供以下能力：

1. **服务目录（Service Catalog）**：统一注册和管理所有微服务、库、基础设施组件，支持元数据标注（Owner、Tier、SLA 等）
2. **软件模板（Software Templates）**：标准化的项目脚手架，一键生成符合组织规范的新服务
3. **技术文档（TechDocs）**：Docs-as-Code，将文档与代码同仓管理，自动同步渲染
4. **自助服务动作（Self-Service Actions）**：通过 UI 或 API 触发标准化操作（如创建数据库、部署环境、申请证书）
5. **可观测性集成**：聚合监控、日志、追踪数据，提供统一的健康度视图
6. **策略与合规**：通过策略引擎（如 OPA）确保资源创建符合安全与合规要求

### Backstage 架构

Backstage 是 Spotify 开源的 IDP 框架，现已进入 CNCF 孵化阶段。其架构分为三层：

```
┌─────────────────────────────────────────────────┐
│              Frontend (React SPA)               │
│   Service Catalog | Templates | TechDocs        │
├─────────────────────────────────────────────────┤
│              Backend (Node.js)                  │
│   Plugin System | Entity API | Integration      │
├─────────────────────────────────────────────────┤
│              Integrations                       │
│   GitHub | GitLab | K8s | AWS | GCP | Jenkins   │
└─────────────────────────────────────────────────┘
```

核心数据模型是 **Entity（实体）**，采用 YAML 格式定义，支持 Component、System、API、Resource、User、Group 等类型。

## 实战/示例

### 最小化 Backstage 部署

以下是一个基于 Docker Compose 的 Backstage 最小化部署示例，包含 PostgreSQL 数据库和 Backstage 应用。

**前置条件**：
- Docker + Docker Compose v2+
- Node.js 18+（用于本地开发）
- GitHub Token（用于集成 GitHub）

#### Step 1: 创建项目结构

```bash
mkdir backstage-demo && cd backstage-demo
mkdir -p app/postgres
```

#### Step 2: 编写 Docker Compose 配置

创建 `docker-compose.yml`：

```yaml
version: '3.8'

services:
  postgres:
    image: postgres:15-alpine
    container_name: backstage-postgres
    environment:
      POSTGRES_USER: backstage
      POSTGRES_PASSWORD: backstage_password
      POSTGRES_DB: backstage
    volumes:
      - ./app/postgres:/var/lib/postgresql/data
    ports:
      - "5432:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U backstage"]
      interval: 5s
      timeout: 5s
      retries: 5

  backstage:
    image: ghcr.io/backstage/backstage:latest
    container_name: backstage-app
    depends_on:
      postgres:
        condition: service_healthy
    environment:
      POSTGRES_HOST: postgres
      POSTGRES_PORT: 5432
      POSTGRES_USER: backstage
      POSTGRES_PASSWORD: backstage_password
      POSTGRES_DB: backstage
      GITHUB_TOKEN: ${GITHUB_TOKEN}
    ports:
      - "7007:7007"
    volumes:
      - ./app-config.local.yaml:/app/app-config.local.yaml
```

#### Step 3: 配置应用

创建 `app-config.local.yaml`：

```yaml
app:
  title: My Company IDP
  baseUrl: http://localhost:7007

backend:
  baseUrl: http://localhost:7007
  listen:
    port: 7007
  database:
    client: pg
    connection:
      host: ${POSTGRES_HOST}
      port: ${POSTGRES_PORT}
      user: ${POSTGRES_USER}
      password: ${POSTGRES_PASSWORD}
      database: ${POSTGRES_DB}

integrations:
  github:
    - host: github.com
      token: ${GITHUB_TOKEN}

catalog:
  locations:
    - type: url
      target: https://github.com/your-org/backstage-catalog-entities/blob/main/entities.yaml
      rules:
        - allow: [Component, System, API, Resource]
```

#### Step 4: 启动服务

```bash
# 设置环境变量
export GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx

# 启动
docker compose up -d

# 查看日志
docker compose logs -f backstage
```

访问 `http://localhost:7007` 即可看到 Backstage UI。

#### Step 5: 注册第一个 Component

在 GitHub 仓库中创建 `entities.yaml`：

```yaml
apiVersion: backstage.io/v1alpha1
kind: Component
metadata:
  name: payment-service
  description: 支付服务 - 处理订单支付与退款
  annotations:
    github.com/project-slug: your-org/payment-service
    backstage.io/techdocs-ref: dir:.
  tags:
    - java
    - spring-boot
    - payment
  links:
    - url: https://github.com/your-org/payment-service
      title: GitHub Repo
    - url: https://api.your-company.com/payment/docs
      title: API Docs
spec:
  type: service
  lifecycle: production
  owner: platform-team
  system: payment-system
  providesApis:
    - payment-api
```

### 创建软件模板

软件模板是 IDP 的核心价值之一。以下是一个简单的 Spring Boot 服务模板定义（`template.yaml`）：

```yaml
apiVersion: scaffolder.backstage.io/v1beta3
kind: Template
metadata:
  name: spring-boot-service
  title: Spring Boot 微服务
  description: 创建一个新的 Spring Boot 微服务项目
  tags:
    - java
    - spring-boot
    - microservice
spec:
  owner: platform-team
  type: service

  parameters:
    - title: 服务信息
      required:
        - name
        - description
        - owner
      properties:
        name:
          title: 服务名称
          type: string
          description: 服务的唯一标识（kebab-case）
          pattern: '^[a-z][a-z0-9-]*$'
        description:
          title: 服务描述
          type: string
          description: 服务的简要描述
        owner:
          title: 负责人
          type: string
          description: 团队或个人的 User/Group Entity
          ui:field: OwnerPicker
          ui:options:
            allowedKinds:
              - User
              - Group

    - title: GitHub 配置
      required:
        - repoUrl
      properties:
        repoUrl:
          title: 仓库地址
          type: string
          ui:field: RepoUrlPicker
          ui:options:
            allowedHosts:
              - github.com

  steps:
    - id: fetch-template
      name: 获取模板
      action: fetch:template
      input:
        url: ./template
        values:
          name: ${{ parameters.name }}
          description: ${{ parameters.description }}
          owner: ${{ parameters.owner }}

    - id: publish-github
      name: 发布到 GitHub
      action: publish:github
      input:
        allowedHosts: ['github.com']
        description: ${{ parameters.description }}
        repoUrl: ${{ parameters.repoUrl }}
        defaultBranch: main

    - id: register-component
      name: 注册到 Catalog
      action: catalog:register
      input:
        repoContentsUrl: ${{ steps['publish-github'].output.repoContentsUrl }}
        catalogInfoPath: '/catalog-info.yaml'
```

## 常见坑与排查

### 坑 1：Catalog 实体同步失败

**现象**：新创建的 Component 在 UI 中不显示，或显示 "Processing" 状态。

**排查步骤**：
1. 检查 Backend 日志中的 `catalog` 相关错误
2. 验证 YAML 格式是否正确（使用 `yamllint` 或 Backstage 的 YAML 校验工具）
3. 确认 Entity 的 `metadata.name` 符合 DNS 命名规范（小写字母、数字、连字符）
4. 检查 Location 的访问权限（GitHub Token 是否有读权限）

```bash
# 查看 Catalog 处理日志
docker compose logs backstage | grep -i "catalog\|entity"

# 手动触发刷新（通过 API）
curl -X POST http://localhost:7007/api/catalog/refresh \
  -H "Content-Type: application/json" \
  -d '{"entityRef": "component:default/payment-service"}'
```

### 坑 2：数据库迁移失败

**现象**：Backstage 启动时报 `relation "xxx" does not exist` 错误。

**原因**：PostgreSQL 数据库未正确初始化或迁移脚本未执行。

**解决方案**：
```bash
# 删除已有数据（开发环境）
docker compose down -v

# 重新启动，Backstage 会自动执行迁移
docker compose up -d

# 检查迁移状态
docker compose logs backstage | grep "migration"
```

### 坑 3：TechDocs 渲染空白

**现象**：TechDocs 页面加载后显示空白或 "No content"。

**排查**：
1. 确认 `backstage.io/techdocs-ref` annotation 指向正确的路径
2. 检查 `mkdocs.yaml` 是否存在且格式正确
3. 验证 TechDocs Generator 是否有权限访问源码仓库
4. 查看 `techdocs` 容器的日志（如果使用了独立 Generator）

```yaml
# mkdocs.yaml 示例
site_name: Payment Service Docs
nav:
  - Home: index.md
  - API: api.md
plugins:
  - techdocs-core
```

### 坑 4：模板执行卡住

**现象**：点击 Create 后，任务长时间处于 "Running" 状态。

**排查**：
1. 检查 `scaffolder` 相关日志
2. 验证 GitHub Token 是否有写权限
3. 确认模板中的 `action` 名称拼写正确
4. 检查网络连通性（尤其是访问外部服务时）

## Checklist

在规划和落地 IDP 时，请参考以下 CheckList：

### 阶段一：评估与规划
- [ ] 明确平台目标：解决什么问题？服务哪些团队？
- [ ] 评估现有工具链：CI/CD、监控、文档系统的现状
- [ ] 确定平台团队的组织架构与职责边界
- [ ] 制定成功度量指标（开发者满意度、采用率、交付时间）

### 阶段二：基础建设
- [ ] 部署 Backstage 或其他 IDP 框架
- [ ] 配置与源代码管理系统的集成（GitHub/GitLab）
- [ ] 建立 Service Catalog 的初始实体（核心服务）
- [ ] 配置 SSO/身份认证（OIDC/SAML）

### 阶段三：能力建设
- [ ] 创建 2-3 个高频使用的软件模板
- [ ] 集成 CI/CD 系统（Jenkins/GitHub Actions/ArgoCD）
- [ ] 接入监控告警系统（Prometheus/Datadog）
- [ ] 建立 TechDocs 的文档规范与同步流程

### 阶段四：运营与迭代
- [ ] 建立平台反馈渠道（Slack 频道、定期调研）
- [ ] 制定平台 SLA 与支持流程
- [ ] 定期审查模板与集成的使用情况
- [ ] 规划 Roadmap，持续迭代平台能力

### 安全与合规
- [ ] 配置 RBAC 权限模型（不同角色的访问控制）
- [ ] 审计日志开启并接入 SIEM 系统
- [ ] 敏感信息（Token、密码）使用密钥管理系统
- [ ] 通过 OPA 或其他策略引擎实施合规检查

## 参考资料

1. **Backstage 官方文档** - https://backstage.io/docs
   - 最权威的 Backstage 使用指南，包含安装、配置、插件开发等完整内容

2. **CNCF Platform Engineering WG** - https://github.com/cncf/tag-app-delivery/tree/main/platform-engineering-wg
   - CNCF 平台工程工作组，提供行业标准与最佳实践

3. **Spotify Backstage 技术博客** - https://backstage.spotify.com/
   - Spotify 团队分享 Backstage 的设计思路与演进历程

4. **Gartner: Platform Engineering Market Guide** - https://www.gartner.com/en/documents/4023982
   - 平台工程市场分析报告（需订阅）

5. **Humanitec Platform Engineering Portal** - https://humanitec.com/platform-engineering
   - 商业 IDP 解决方案，提供参考架构与案例

---

*本文档是 daily-tech-notes 系列的第 98 篇，聚焦 Platform Engineering 与 IDP 落地实践。*
