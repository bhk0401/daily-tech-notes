# Infrastructure as Code：Terraform 基础与最佳实践

## 背景与目标

在现代云原生架构中，基础设施的管理已经从手动点击控制台演变为代码驱动的模式。Infrastructure as Code (IaC) 通过将基础设施配置写成代码文件，实现了版本控制、可重复部署和团队协作。

Terraform 是 HashiCorp 开发的开源 IaC 工具，采用声明式配置语言 HCL (HashiCorp Configuration Language)。它的核心优势在于：

- **多云支持**：同一套语法可以管理 AWS、Azure、GCP、阿里云等 200+ 云提供商
- **状态管理**：通过 state 文件追踪资源变更，支持增量更新
- **依赖图计算**：自动分析资源依赖关系，按正确顺序创建/销毁资源
- **模块化设计**：支持模块复用，构建可组合的基础设施组件

本文目标是通过一个完整的示例，帮助读者掌握 Terraform 的核心概念、最佳实践和常见排障方法，能够在实际项目中快速上手。

## 核心概念

### 1. Provider（提供商）

Provider 是 Terraform 与云 API 交互的插件。每个云服务商都有对应的 provider，例如：

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}
```

### 2. Resource（资源）

Resource 是基础设施的基本单元，代表一个云资源（如 EC2 实例、S3 存储桶、RDS 数据库等）：

```hcl
resource "aws_s3_bucket" "my_bucket" {
  bucket = "my-unique-bucket-name-2026"
  
  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}
```

### 3. State（状态）

Terraform 通过 `terraform.tfstate` 文件记录当前基础设施的实际状态。这个文件至关重要：

- 用于比对期望状态与实际状态的差异
- 存储资源的唯一标识符和元数据
- **必须安全存储**（推荐远程 backend 如 S3 + DynamoDB 锁）

### 4. Variables & Outputs（变量与输出）

变量使配置可参数化，输出用于模块间传递信息：

```hcl
variable "environment" {
  type    = string
  default = "dev"
}

output "bucket_name" {
  value = aws_s3_bucket.my_bucket.bucket
}
```

### 5. Modules（模块）

模块是可复用的配置单元，支持封装复杂逻辑：

```
modules/
├── vpc/
│   ├── main.tf
│   ├── variables.tf
│   └── outputs.tf
└── eks/
    ├── main.tf
    └── ...
```

## 实战/示例

下面是一个完整的示例，展示如何用 Terraform 创建一个带版本控制的 S3 存储桶，并配置访问日志：

### 项目结构

```
terraform-s3-example/
├── main.tf
├── variables.tf
├── outputs.tf
├── terraform.tfvars
└── backend.tf
```

### main.tf

```hcl
# S3 存储桶（带版本控制和加密）
resource "aws_s3_bucket" "data_bucket" {
  bucket = var.bucket_name
  
  tags = {
    Name        = var.bucket_name
    Environment = var.environment
    Project     = var.project_name
  }
}

# 启用版本控制
resource "aws_s3_bucket_versioning" "data_bucket_versioning" {
  bucket = aws_s3_bucket.data_bucket.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# 启用服务端加密（SSE-S3）
resource "aws_s3_bucket_server_side_encryption_configuration" "data_bucket_encryption" {
  bucket = aws_s3_bucket.data_bucket.id
  
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# 配置访问日志
resource "aws_s3_bucket" "log_bucket" {
  bucket = "${var.bucket_name}-logs"
  
  tags = {
    Name = "${var.bucket_name}-logs"
  }
}

resource "aws_s3_bucket_logging" "data_bucket_logging" {
  bucket = aws_s3_bucket.data_bucket.id
  
  target_bucket = aws_s3_bucket.log_bucket.id
  target_prefix = "access-logs/"
}

# 生命周期规则：30 天后转为 IA，90 天后归档
resource "aws_s3_bucket_lifecycle_configuration" "data_bucket_lifecycle" {
  bucket = aws_s3_bucket.data_bucket.id
  
  rule {
    id     = "transition-to-ia"
    status = "Enabled"
    
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
    
    transition {
      days          = 90
      storage_class = "GLACIER"
    }
  }
}
```

### variables.tf

```hcl
variable "bucket_name" {
  description = "S3 bucket name (must be globally unique)"
  type        = string
  
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{2,62}[a-z0-9]$", var.bucket_name))
    error_message = "Bucket name must be 3-63 characters, lowercase letters, numbers, and hyphens only."
  }
}

variable "environment" {
  description = "Environment name (dev/staging/prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project identifier for tagging"
  type        = string
  default     = "unknown"
}
```

### outputs.tf

```hcl
output "bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.data_bucket.arn
}

output "bucket_name" {
  description = "Name of the S3 bucket"
  value       = aws_s3_bucket.data_bucket.bucket
}

output "log_bucket_name" {
  description = "Name of the logging bucket"
  value       = aws_s3_bucket.log_bucket.bucket
}
```

### terraform.tfvars

```hcl
bucket_name  = "my-app-data-prod-2026"
environment  = "production"
project_name = "data-pipeline"
```

### 执行流程

```bash
# 1. 初始化（下载 provider 插件）
terraform init

# 2. 格式化检查
terraform fmt -check

# 3. 验证配置
terraform validate

# 4. 预览变更
terraform plan -out=tfplan

# 5. 应用变更
terraform apply tfplan

# 6. 查看输出
terraform output
```

### demos 目录示例

仓库中 `demos/terraform-s3/` 目录包含完整可运行示例，可直接克隆后执行：

```bash
git clone https://github.com/bhk0401/daily-tech-notes.git
cd daily-tech-notes/demos/terraform-s3
terraform init && terraform apply
```

## 常见坑与排障

### 1. State 文件锁定冲突

**现象**：`Error: Failed to lock state file`

**原因**：多个用户同时执行 terraform apply，或上次执行异常退出未释放锁。

**解决**：
```bash
# 检查锁状态
terraform force-unlock <LOCK_ID>

# 预防：使用远程 backend + DynamoDB 锁
```

### 2. Provider 版本不兼容

**现象**：`Error: Failed to instantiate provider`

**原因**：terraform init 时未指定版本约束，升级后 API 变更导致。

**解决**：
```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"  # 锁定大版本
    }
  }
}
```

### 3. 资源被手动删除

**现象**：`terraform plan` 显示要重建资源，但实际上资源已不存在。

**原因**：有人在控制台手动删除了资源，但 state 文件未更新。

**解决**：
```bash
# 从 state 中移除资源引用
terraform state rm aws_s3_bucket.data_bucket

# 或者重新导入
terraform import aws_s3_bucket.data_bucket <bucket-name>
```

### 4. 敏感信息泄露

**现象**：state 文件中包含密码、密钥等敏感信息。

**解决**：
```hcl
# 使用 sensitive 标记
variable "db_password" {
  type      = string
  sensitive = true
}

# 使用 Secrets Manager 而非硬编码
data "aws_secretsmanager_secret_version" "creds" {
  secret_id = "prod/db/credentials"
}
```

### 5. 依赖顺序错误

**现象**：资源创建失败，提示依赖的资源不存在。

**解决**：使用 `depends_on` 显式声明依赖：
```hcl
resource "aws_instance" "app" {
  # ...
  depends_on = [aws_vpc.main, aws_subnet.private]
}
```

## Checklist

部署前的检查清单：

- [ ] **代码审查**
  - [ ] terraform fmt 格式化通过
  - [ ] terraform validate 验证通过
  - [ ] 敏感信息已使用变量或 Secrets Manager
  - [ ] 资源标签（tags）完整

- [ ] **状态管理**
  - [ ] 使用远程 backend（S3/GCS/Azure Blob）
  - [ ] 启用 state 文件版本控制
  - [ ] 配置状态锁（DynamoDB/其他）
  - [ ] 限制 state 文件访问权限

- [ ] **安全合规**
  - [ ] 所有存储启用加密
  - [ ] 网络资源配置安全组/防火墙
  - [ ] IAM 角色遵循最小权限原则
  - [ ] 启用访问日志和监控

- [ ] **变更管理**
  - [ ] terraform plan 输出已审查
  - [ ] 变更在测试环境验证过
  - [ ] 有回滚方案（state 备份）
  - [ ] 变更窗口已通知相关方

- [ ] **成本优化**
  - [ ] 资源规格符合实际需求
  - [ ] 配置生命周期策略（自动归档/删除）
  - [ ] 未使用的资源已清理
  - [ ] 预留实例/ Savings Plans 已评估

## 参考资料

1. **Terraform 官方文档** - 最权威的学习资源，包含完整的语言规范、provider 文档和最佳实践指南
   https://developer.hashicorp.com/terraform/docs

2. **Terraform Registry** - 查找和浏览所有官方及社区维护的 provider 和模块
   https://registry.terraform.io/

3. **HashiCorp Learn: Terraform** - 免费的交互式教程，从入门到高级主题
   https://developer.hashicorp.com/terraform/tutorials

4. **Awesome Terraform** - 社区维护的工具、模块、文章合集
   https://github.com/shuaibiyy/awesome-terraform

5. **Terraform Up & Running (书籍)** - Yevgeniy Brikman 著，深入讲解生产级 Terraform 实践
   https://www.terraformupandrunning.com/

---

*本文档遵循 CC BY 4.0 协议，代码示例遵循 MIT 许可证。*
