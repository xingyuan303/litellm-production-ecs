# LiteLLM Production ECS Deployment

企业级 LiteLLM 部署方案，基于 AWS ECS Fargate、RDS PostgreSQL、Application Load Balancer，支持自动扩展和高可用。

## ✨ 特性

- ✅ **高可用架构**: Multi-AZ 部署，ALB 负载均衡
- ✅ **自动扩展**: 基于 CPU/内存/请求数量的自动扩展 (2-10 实例)
- ✅ **托管数据库**: RDS PostgreSQL Multi-AZ，自动备份和恢复
- ✅ **HTTPS 支持**: Route53 + ACM 自动证书管理
- ✅ **安全加固**: Secrets Manager、加密存储、网络隔离
- ✅ **监控告警**: CloudWatch 指标和告警，Performance Insights
- ✅ **最新版本**: 使用 LiteLLM main-stable 分支
- ✅ **生产就绪**: 包含完整的部署文档和故障排查指南

## 🏗️ 架构

```
┌─────────────┐
│   Internet  │
└──────┬──────┘
       │
┌──────▼──────┐
│  Route53    │  (可选: 自定义域名)
└──────┬──────┘
       │
┌──────▼──────────────────────────────┐
│   Application Load Balancer         │
│   (Multi-AZ, HTTPS/HTTP)           │
└──────┬──────────────────────────────┘
       │
┌──────▼────────────────────────────────┐
│      ECS Fargate Cluster              │
│  ┌─────┐  ┌─────┐       ┌─────┐     │
│  │Task │  │Task │  ...  │Task │     │
│  │4vCPU│  │4vCPU│       │4vCPU│     │
│  │ 8GB │  │ 8GB │       │ 8GB │     │
│  └──┬──┘  └──┬──┘       └──┬──┘     │
└─────┼────────┼──────────────┼────────┘
      └────────┴──────────────┘
               │
      ┌────────▼─────────┐
      │  RDS PostgreSQL  │
      │   (Multi-AZ)     │
      └──────────────────┘
```

## 📋 组件清单

| 组件 | 说明 | 数量 |
|-----|------|------|
| **ECS Fargate** | 无服务器容器 (4 vCPU, 8GB RAM) | 2-10 (自动扩展) |
| **RDS PostgreSQL** | 托管数据库 (Multi-AZ) | 1 |
| **Application Load Balancer** | 负载均衡器 (Multi-AZ) | 1 |
| **Route53 + ACM** | DNS 和 SSL 证书 (可选) | 1 |
| **Secrets Manager** | 密钥管理 | 多个 |
| **CloudWatch** | 日志和监控 | 1 |
| **Auto Scaling** | 自动扩展策略 | 3 (CPU/内存/请求) |

## 🚀 快速开始

### 1. 前置要求

```bash
# 安装依赖
- AWS CLI >= 2.0
- Terraform >= 1.0
- Docker with buildx

# 配置 AWS 凭证
aws configure --profile litellm-prod
```

### 2. 配置

```bash
# 复制配置文件
cp terraform.tfvars.example terraform.tfvars

# 编辑配置 (最小化配置)
cat > terraform.tfvars <<EOF
project_name = "litellm"
aws_region   = "us-east-1"

# 生成安全密钥
litellm_master_key = "sk-$(openssl rand -hex 16)"
litellm_salt_key   = "$(openssl rand -hex 32)"

# 添加至少一个 API Key
openai_api_key = "sk-proj-your-key"

# 数据库配置
db_instance_class = "db.t3.medium"
db_multi_az       = true

# 禁用 HTTPS (测试用)
enable_https = false
EOF
```

### 3. 部署

```bash
# 初始化
terraform init

# 部署基础设施 (15-20 分钟)
terraform apply

# 构建并推送 Docker 镜像
ECR_URL=$(terraform output -raw ecr_repository_url)
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $ECR_URL
docker buildx build --platform linux/amd64 -t litellm:latest .
docker tag litellm:latest $ECR_URL:latest
docker push $ECR_URL:latest

# 强制 ECS 更新
aws ecs update-service \
  --cluster $(terraform output -raw ecs_cluster_name) \
  --service $(terraform output -raw ecs_service_name) \
  --force-new-deployment \
  --region us-east-1
```

### 4. 验证

```bash
# 获取访问 URL
ALB_URL=$(terraform output -raw alb_url_http)

# 测试健康检查
curl $ALB_URL/health

# 测试 API
curl $ALB_URL/v1/models \
  -H "Authorization: Bearer $(terraform output -raw litellm_master_key)"
```

## 📖 完整文档

详细的部署指南、配置说明、故障排查请查看:

➡️ **[DEPLOYMENT.md](./DEPLOYMENT.md)** ⬅️

包含内容:
- 详细配置选项
- 逐步部署指南
- HTTPS 配置
- 监控和告警设置
- 故障排查指南
- 成本估算
- 安全最佳实践

## 📊 Terraform 资源

### 核心文件

| 文件 | 说明 |
|-----|------|
| `alb.tf` | Application Load Balancer 和安全组 |
| `rds.tf` | RDS PostgreSQL 数据库配置 |
| `route53.tf` | Route53 DNS 和 ACM 证书 |
| `autoscaling.tf` | ECS 自动扩展策略和告警 |
| `service.tf` | ECS 服务定义 |
| `taskdefinition.tf` | ECS 任务定义 |
| `ecs.tf` | ECS 集群 |
| `ecr.tf` | ECR 容器仓库 |
| `vpc.tf` | VPC 和子网配置 |
| `iam.tf` | IAM 角色和策略 |
| `secrets.tf` | Secrets Manager 配置 |
| `variables.tf` | 输入变量定义 |
| `outputs.tf` | 输出变量定义 |

### 辅助文件

| 文件 | 说明 |
|-----|------|
| `terraform.tfvars.example` | 配置示例 |
| `build.sh` | Docker 镜像构建脚本 |
| `Dockerfile` | 容器镜像定义 |
| `config.yaml` | LiteLLM 配置文件 |

## ⚙️ 关键配置

### 自动扩展

```hcl
# 容量范围
ecs_min_capacity = 2    # 最少 2 个实例
ecs_max_capacity = 10   # 最多 10 个实例

# 扩展触发条件
cpu_target_value    = 70   # CPU 70%
memory_target_value = 75   # 内存 75%
```

### 数据库

```hcl
# 实例类型
db_instance_class = "db.t3.medium"  # 2 vCPU, 4GB RAM

# 高可用
db_multi_az = true  # 生产环境推荐

# 存储自动扩展
db_allocated_storage     = 100   # 初始 100GB
db_max_allocated_storage = 500   # 最大 500GB
```

### HTTPS (可选)

```hcl
enable_https      = true
domain_name       = "example.com"
litellm_subdomain = "litellm.example.com"
```

## 💰 成本估算

### 最小配置 (~$482/月)
- 2 个 ECS 任务 (4vCPU, 8GB): ~$288/月
- RDS db.t3.medium Multi-AZ: ~$164/月
- ALB: ~$23/月
- 其他: ~$7/月

### 生产配置 (~$1,069/月)
- 平均 4 个 ECS 任务: ~$576/月
- RDS db.r6g.xlarge Multi-AZ: ~$450/月
- ALB: ~$23/月
- 其他: ~$20/月

**优化建议**: 使用 AWS Savings Plans 可节省最多 50-70%

## 🔧 常用命令

```bash
# 查看服务状态
aws ecs describe-services \
  --cluster $(terraform output -raw ecs_cluster_name) \
  --services $(terraform output -raw ecs_service_name)

# 查看日志
aws logs tail /ecs/litellm --follow

# 手动扩展
aws ecs update-service \
  --cluster $(terraform output -raw ecs_cluster_name) \
  --service $(terraform output -raw ecs_service_name) \
  --desired-count 5

# 强制更新 (重新部署)
aws ecs update-service \
  --cluster $(terraform output -raw ecs_cluster_name) \
  --service $(terraform output -raw ecs_service_name) \
  --force-new-deployment

# 获取数据库密码
aws secretsmanager get-secret-value \
  --secret-id litellm/db_password \
  --query SecretString \
  --output text
```

## 📈 监控

自动创建的 CloudWatch 告警:
- ✅ ECS CPU/内存使用率
- ✅ ECS 最大容量告警
- ✅ RDS CPU/内存/存储
- ✅ ALB 目标健康状态
- ✅ ALB 5XX 错误率
- ✅ ALB 响应时间

查看告警:
```bash
aws cloudwatch describe-alarms \
  --alarm-name-prefix litellm
```

## 🔐 安全

- ✅ 所有敏感数据存储在 Secrets Manager
- ✅ RDS 数据库加密
- ✅ ECS 任务在私有子网
- ✅ 安全组最小化权限
- ✅ HTTPS 传输加密
- ✅ IAM 角色最小权限

## 🚨 故障排查

### ECS 任务无法启动

```bash
# 查看任务失败原因
aws ecs describe-tasks --cluster litellm-ecs-cluster \
  --tasks $(aws ecs list-tasks --cluster litellm-ecs-cluster --query 'taskArns[0]' --output text)

# 查看日志
aws logs tail /ecs/litellm --follow
```

### ALB 健康检查失败

```bash
# 查看目标健康状态
aws elbv2 describe-target-health \
  --target-group-arn $(aws elbv2 describe-target-groups --names litellm-tg --query 'TargetGroups[0].TargetGroupArn' --output text)
```

### 数据库连接失败

```bash
# 检查 RDS 状态
aws rds describe-db-instances --db-instance-identifier litellm-db

# 检查安全组
aws ec2 describe-security-groups \
  --group-ids $(terraform output -raw rds_security_group_id)
```

更多故障排查指南: [DEPLOYMENT.md](./DEPLOYMENT.md#故障排查)

## 🔄 更新和维护

### 更新 LiteLLM 版本

```bash
# 1. 拉取最新代码
git pull

# 2. 重新构建镜像
./build.sh

# 3. ECS 自动更新
```

### 更新 Terraform 配置

```bash
# 1. 修改 terraform.tfvars
vim terraform.tfvars

# 2. 应用变更
terraform plan
terraform apply
```

### 数据库备份

```bash
# 自动备份 (已配置)
# 保留 7 天，每天自动备份

# 手动创建快照
aws rds create-db-snapshot \
  --db-instance-identifier litellm-db \
  --db-snapshot-identifier litellm-manual-$(date +%Y%m%d)
```

## 📚 相关资源

- [LiteLLM 官方文档](https://docs.litellm.ai)
- [LiteLLM GitHub](https://github.com/BerriAI/litellm)
- [AWS ECS 最佳实践](https://docs.aws.amazon.com/AmazonECS/latest/bestpracticesguide/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

## 🤝 贡献

欢迎提交 Issue 和 Pull Request!

## 📄 许可证

本项目基于原始 [litellm-ecs-deployment](https://github.com/BerriAI/litellm-ecs-deployment) 项目改进。

---

**下一步:**

1. ✅ 完成快速开始部署
2. ✅ 配置自定义域名 (可选)
3. ✅ 设置监控告警
4. ✅ 配置 CI/CD 自动部署
5. ✅ 实施安全加固

有问题？查看 [DEPLOYMENT.md](./DEPLOYMENT.md) 或提交 Issue。
