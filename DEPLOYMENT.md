# LiteLLM Production Deployment Guide

完整的生产级 LiteLLM 部署指南，包含 ALB、RDS、自动扩展等企业功能。

## 📋 目录

- [架构概览](#架构概览)
- [前置要求](#前置要求)
- [快速开始](#快速开始)
- [详细配置](#详细配置)
- [部署步骤](#部署步骤)
- [验证部署](#验证部署)
- [运维管理](#运维管理)
- [故障排查](#故障排查)
- [成本估算](#成本估算)

## 🏗️ 架构概览

```
Internet
    ↓
Route53 (可选)
    ↓
Application Load Balancer (Multi-AZ)
    ↓
┌─────────────────────────────────────┐
│     ECS Fargate 集群               │
│  ┌──────┐  ┌──────┐  ┌──────┐    │
│  │Task 1│  │Task 2│  │Task N│    │
│  │ 4vCPU│  │ 4vCPU│  │ 4vCPU│    │
│  │ 8GB  │  │ 8GB  │  │ 8GB  │    │
│  └──┬───┘  └──┬───┘  └──┬───┘    │
└─────┼─────────┼─────────┼─────────┘
      └─────────┴─────────┘
              ↓
   RDS PostgreSQL (Multi-AZ)
```

### 核心组件

1. **Application Load Balancer**
   - HTTPS/HTTP 终止
   - 健康检查
   - 跨 3 个可用区

2. **ECS Fargate**
   - 无服务器容器
   - 自动扩展 (2-10 实例)
   - Multi-AZ 部署

3. **RDS PostgreSQL**
   - Multi-AZ 高可用
   - 自动备份
   - 性能洞察

4. **Auto Scaling**
   - CPU 基础扩展
   - 内存基础扩展
   - 请求数量扩展

5. **Route53 + ACM** (可选)
   - 自定义域名
   - SSL/TLS 证书
   - 自动续期

## 📦 前置要求

### 必需工具

```bash
# 1. AWS CLI
aws --version
# 需要 >= 2.0

# 2. Terraform
terraform --version
# 需要 >= 1.0

# 3. Docker (用于构建镜像)
docker --version

# 4. Docker Buildx (多平台构建)
docker buildx version
```

### AWS 权限

需要以下 AWS 服务的权限：
- ECS (Elastic Container Service)
- ECR (Elastic Container Registry)
- RDS (Relational Database Service)
- VPC, Subnets, Security Groups
- Application Load Balancer
- Route53 (如果使用自定义域名)
- ACM (如果使用 HTTPS)
- Secrets Manager
- CloudWatch Logs
- IAM Roles

### AWS 账户配置

```bash
# 配置 AWS CLI
aws configure --profile litellm-prod

# 输入信息:
# AWS Access Key ID: AKIA...
# AWS Secret Access Key: ...
# Default region: us-east-1
# Default output format: json

# 验证配置
aws sts get-caller-identity --profile litellm-prod
```

## 🚀 快速开始

### 1. 克隆或创建项目

```bash
# 创建项目目录
mkdir litellm-production-ecs
cd litellm-production-ecs

# 所有 Terraform 文件已在当前目录
```

### 2. 配置变量

```bash
# 复制示例配置文件
cp terraform.tfvars.example terraform.tfvars

# 编辑配置文件
vim terraform.tfvars
```

**最小化配置示例** (不使用 HTTPS):

```hcl
# terraform.tfvars

project_name = "litellm"
environment  = "production"
aws_region   = "us-east-1"

# LiteLLM 配置
litellm_master_key = "sk-1234567890abcdef"  # 替换为你的密钥
litellm_salt_key   = "your-salt-key-here"   # 替换为你的盐值

# API Keys (至少配置一个)
openai_api_key    = "sk-proj-..."
anthropic_api_key = "sk-ant-..."

# 数据库配置
db_instance_class = "db.t3.medium"
db_multi_az       = true

# ECS 配置
ecs_desired_count = 2
ecs_min_capacity  = 2
ecs_max_capacity  = 10

# 禁用 HTTPS (用于测试)
enable_https = false
```

**完整配置示例** (包含 HTTPS):

```hcl
# terraform.tfvars

project_name = "litellm"
environment  = "production"
aws_region   = "us-east-1"

# 启用 HTTPS
enable_https      = true
domain_name       = "example.com"          # 你的根域名
litellm_subdomain = "litellm.example.com"  # LiteLLM 子域名

# LiteLLM 配置
litellm_master_key = "sk-1234567890abcdef"
litellm_salt_key   = "your-salt-key-here"

# API Keys
openai_api_key    = "sk-proj-..."
anthropic_api_key = "sk-ant-..."
azure_api_key     = "your-azure-key"

# 其他配置...
```

### 3. 初始化 Terraform

```bash
# 初始化
terraform init

# 查看执行计划
terraform plan

# 预览将要创建的资源数量
```

### 4. 部署基础设施

```bash
# 应用配置
terraform apply

# 确认后输入: yes

# 部署时间: 约 15-20 分钟
```

### 5. 构建并推送 Docker 镜像

```bash
# 获取 ECR 仓库 URL
ECR_URL=$(terraform output -raw ecr_repository_url)

# 登录 ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin $ECR_URL

# 构建镜像
docker buildx build --platform linux/amd64 -t litellm:latest .

# 标记镜像
docker tag litellm:latest $ECR_URL:latest

# 推送镜像
docker push $ECR_URL:latest

# 强制 ECS 更新
aws ecs update-service \
  --cluster $(terraform output -raw ecs_cluster_name) \
  --service $(terraform output -raw ecs_service_name) \
  --force-new-deployment \
  --region us-east-1
```

### 6. 验证部署

```bash
# 获取访问 URL
terraform output alb_url_http
# 或
terraform output custom_domain_url

# 测试健康检查
curl http://<alb-dns>/health

# 测试 API
curl http://<alb-dns>/v1/models \
  -H "Authorization: Bearer sk-1234567890abcdef"
```

## ⚙️ 详细配置

### 数据库配置选项

```hcl
# 实例类型
db_instance_class = "db.t3.medium"   # 2 vCPU, 4GB RAM
# db_instance_class = "db.t3.large"  # 2 vCPU, 8GB RAM
# db_instance_class = "db.r6g.xlarge" # 4 vCPU, 32GB RAM

# 存储
db_allocated_storage     = 100  # 初始 100GB
db_max_allocated_storage = 500  # 自动扩展到 500GB

# 高可用
db_multi_az = true  # 生产环境强烈推荐

# 备份
db_backup_retention_period = 7  # 保留 7 天备份
```

### 自动扩展配置

```hcl
# 容量范围
ecs_min_capacity = 2   # 最少 2 个实例
ecs_max_capacity = 10  # 最多 10 个实例

# 触发条件
cpu_target_value    = 70  # CPU 达到 70% 时扩展
memory_target_value = 75  # 内存达到 75% 时扩展

# 请求数量触发
alb_request_count_target = 1000  # 每个实例 1000 请求/分钟
```

### 定时扩展 (可选)

```hcl
enable_scheduled_scaling = true

# 早上 8 点扩展到 4-10 个实例
scheduled_scale_up_min = 4
scheduled_scale_up_max = 10

# 晚上 8 点缩减到 2-4 个实例
scheduled_scale_down_min = 2
scheduled_scale_down_max = 4
```

### 监控告警配置

```hcl
# 创建 SNS Topic
# 1. 在 AWS 控制台创建 SNS Topic
# 2. 订阅你的邮箱
# 3. 确认订阅邮件

alarm_sns_topic_arn = "arn:aws:sns:us-east-1:123456789012:litellm-alerts"
```

## 📝 部署步骤详解

### 步骤 1: 准备 Route53 域名 (如果使用 HTTPS)

```bash
# 1. 确认 Route53 Hosted Zone 存在
aws route53 list-hosted-zones --query "HostedZones[?Name=='example.com.']"

# 2. 如果不存在，创建 Hosted Zone
aws route53 create-hosted-zone \
  --name example.com \
  --caller-reference $(date +%s)

# 3. 更新域名注册商的 NS 记录
# 将域名的 NS 记录指向 Route53 的 name servers
```

### 步骤 2: 生成安全密钥

```bash
# 生成 Master Key
openssl rand -hex 32
# 输出: sk-abc123...

# 生成 Salt Key
openssl rand -hex 32
# 输出: def456...

# 将这些密钥填入 terraform.tfvars
```

### 步骤 3: 配置 API Keys

```bash
# 编辑 terraform.tfvars
vim terraform.tfvars

# 添加 API Keys
openai_api_key    = "sk-proj-..."
anthropic_api_key = "sk-ant-..."
azure_api_key     = "..."
```

### 步骤 4: 部署并监控

```bash
# 部署
terraform apply

# 实时监控部署进度
watch -n 5 'aws ecs describe-services \
  --cluster litellm-ecs-cluster \
  --services litellm-service \
  --query "services[0].{RunningCount:runningCount,DesiredCount:desiredCount,Status:status}" \
  --output table'
```

### 步骤 5: 配置 LiteLLM

创建 `config.yaml`:

```yaml
model_list:
  - model_name: gpt-4
    litellm_params:
      model: openai/gpt-4
      api_key: os.environ/OPENAI_API_KEY

  - model_name: claude-sonnet-4
    litellm_params:
      model: anthropic/claude-sonnet-4-20250514
      api_key: os.environ/ANTHROPIC_API_KEY

  - model_name: gpt-35-turbo
    litellm_params:
      model: azure/gpt-35-turbo
      api_base: os.environ/AZURE_API_BASE
      api_key: os.environ/AZURE_API_KEY

litellm_settings:
  drop_params: true
  set_verbose: false

general_settings:
  master_key: os.environ/LITELLM_MASTER_KEY
  database_url: os.environ/DATABASE_URL
```

重新构建并部署:

```bash
# 重新构建包含 config.yaml 的镜像
docker buildx build --platform linux/amd64 -t litellm:latest .
docker tag litellm:latest $ECR_URL:latest
docker push $ECR_URL:latest

# 强制更新
./build.sh
```

## ✅ 验证部署

### 1. 检查基础设施

```bash
# ECS 服务状态
aws ecs describe-services \
  --cluster litellm-ecs-cluster \
  --services litellm-service

# RDS 状态
aws rds describe-db-instances \
  --db-instance-identifier litellm-db

# ALB 健康检查
aws elbv2 describe-target-health \
  --target-group-arn $(terraform output -raw target_group_arn)
```

### 2. 测试健康端点

```bash
# HTTP
curl http://$(terraform output -raw alb_dns_name)/health

# HTTPS (如果启用)
curl https://litellm.example.com/health

# 预期输出
{"status": "healthy"}
```

### 3. 测试 API

```bash
# 列出模型
curl https://litellm.example.com/v1/models \
  -H "Authorization: Bearer sk-1234567890abcdef"

# 预期输出
{
  "data": [
    {"id": "gpt-4", ...},
    {"id": "claude-sonnet-4", ...}
  ]
}
```

### 4. 测试完整请求

```bash
curl https://litellm.example.com/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer sk-1234567890abcdef" \
  -d '{
    "model": "gpt-4",
    "messages": [{"role": "user", "content": "Hello"}]
  }'
```

### 5. 查看日志

```bash
# CloudWatch Logs
aws logs tail /ecs/litellm --follow

# 查看最近的错误
aws logs filter-log-events \
  --log-group-name /ecs/litellm \
  --filter-pattern "ERROR"
```

## 🔧 运维管理

### 更新 Docker 镜像

```bash
# 1. 修改代码或配置
# 2. 重新构建
./build.sh

# 或手动:
docker buildx build --platform linux/amd64 -t litellm:latest .
docker tag litellm:latest $ECR_URL:latest
docker push $ECR_URL:latest

# 3. 强制 ECS 更新
aws ecs update-service \
  --cluster litellm-ecs-cluster \
  --service litellm-service \
  --force-new-deployment
```

### 手动扩展

```bash
# 扩展到 5 个实例
aws ecs update-service \
  --cluster litellm-ecs-cluster \
  --service litellm-service \
  --desired-count 5

# 查看扩展状态
aws ecs describe-services \
  --cluster litellm-ecs-cluster \
  --services litellm-service \
  --query "services[0].deployments"
```

### 查看监控指标

```bash
# CPU 使用率
aws cloudwatch get-metric-statistics \
  --namespace AWS/ECS \
  --metric-name CPUUtilization \
  --dimensions Name=ServiceName,Value=litellm-service Name=ClusterName,Value=litellm-ecs-cluster \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average

# 内存使用率
aws cloudwatch get-metric-statistics \
  --namespace AWS/ECS \
  --metric-name MemoryUtilization \
  --dimensions Name=ServiceName,Value=litellm-service Name=ClusterName,Value=litellm-ecs-cluster \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average
```

### 数据库管理

```bash
# 获取数据库密码
aws secretsmanager get-secret-value \
  --secret-id litellm/db_password \
  --query SecretString \
  --output text

# 连接数据库
psql "$(terraform output -raw database_url)"

# 查看数据库大小
SELECT pg_size_pretty(pg_database_size('litellm'));

# 查看表统计
SELECT schemaname, tablename,
       pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename))
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;
```

### 备份和恢复

```bash
# 创建手动快照
aws rds create-db-snapshot \
  --db-instance-identifier litellm-db \
  --db-snapshot-identifier litellm-manual-snapshot-$(date +%Y%m%d-%H%M%S)

# 列出快照
aws rds describe-db-snapshots \
  --db-instance-identifier litellm-db

# 从快照恢复 (创建新实例)
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier litellm-db-restored \
  --db-snapshot-identifier litellm-manual-snapshot-20260324-120000
```

## 🔍 故障排查

### 问题 1: ECS 任务无法启动

**症状**: `terraform apply` 成功，但 ECS 任务数量为 0

**排查步骤**:

```bash
# 1. 查看任务失败原因
aws ecs describe-tasks \
  --cluster litellm-ecs-cluster \
  --tasks $(aws ecs list-tasks --cluster litellm-ecs-cluster --query 'taskArns[0]' --output text) \
  --query 'tasks[0].stoppedReason'

# 2. 查看 CloudWatch 日志
aws logs tail /ecs/litellm --follow

# 3. 常见问题:
# - ECR 镜像不存在: 运行 ./build.sh 构建镜像
# - 环境变量错误: 检查 taskdefinition.tf
# - 数据库连接失败: 检查安全组规则
```

### 问题 2: ALB 健康检查失败

**症状**: ALB 显示所有目标不健康

**排查步骤**:

```bash
# 1. 查看目标健康状态
aws elbv2 describe-target-health \
  --target-group-arn $(aws elbv2 describe-target-groups --names litellm-tg --query 'TargetGroups[0].TargetGroupArn' --output text)

# 2. 检查健康检查配置
aws elbv2 describe-target-groups \
  --names litellm-tg \
  --query 'TargetGroups[0].HealthCheckPath'

# 3. 手动测试健康端点
# 获取任务 IP
TASK_IP=$(aws ecs describe-tasks \
  --cluster litellm-ecs-cluster \
  --tasks $(aws ecs list-tasks --cluster litellm-ecs-cluster --query 'taskArns[0]' --output text) \
  --query 'tasks[0].attachments[0].details[?name==`privateIPv4Address`].value' \
  --output text)

curl http://$TASK_IP:4000/health/readiness
```

### 问题 3: 数据库连接失败

**症状**: 应用启动失败，日志显示数据库连接错误

**排查步骤**:

```bash
# 1. 检查 RDS 状态
aws rds describe-db-instances \
  --db-instance-identifier litellm-db \
  --query 'DBInstances[0].DBInstanceStatus'

# 2. 检查安全组规则
aws ec2 describe-security-groups \
  --group-ids $(aws rds describe-db-instances --db-instance-identifier litellm-db --query 'DBInstances[0].VpcSecurityGroups[0].VpcSecurityGroupId' --output text)

# 3. 测试数据库连接
# 从 ECS 任务内部测试
aws ecs execute-command \
  --cluster litellm-ecs-cluster \
  --task <task-id> \
  --container litellm-container \
  --interactive \
  --command "nc -zv $DB_HOST 5432"
```

### 问题 4: HTTPS 证书验证失败

**症状**: ACM 证书一直处于 "Pending validation" 状态

**排查步骤**:

```bash
# 1. 检查证书状态
aws acm describe-certificate \
  --certificate-arn $(terraform output -raw acm_certificate_arn)

# 2. 检查 Route53 验证记录
aws route53 list-resource-record-sets \
  --hosted-zone-id $(terraform output -raw route53_zone_id) \
  --query "ResourceRecordSets[?Type=='CNAME']"

# 3. 手动验证 DNS
dig _<validation-name>.<your-domain> CNAME

# 4. 等待 DNS 传播 (可能需要 10-30 分钟)
```

### 问题 5: 高延迟或性能问题

**症状**: API 响应时间过长

**排查步骤**:

```bash
# 1. 查看 CloudWatch 指标
# ALB 响应时间
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApplicationELB \
  --metric-name TargetResponseTime \
  --dimensions Name=LoadBalancer,Value=$(terraform output -raw alb_arn | cut -d'/' -f2-) \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average

# 2. 检查 ECS CPU/内存使用
# 如果持续高于 80%，考虑:
# - 增加任务 CPU/内存
# - 降低 auto scaling 阈值
# - 增加最大实例数

# 3. 检查数据库性能
aws rds describe-db-instances \
  --db-instance-identifier litellm-db \
  --query 'DBInstances[0].{CPU:CPUUtilization,Connections:DatabaseConnections}'

# 4. 启用 Performance Insights
# 在 AWS RDS 控制台查看慢查询
```

## 💰 成本估算

### 按月成本估算 (us-east-1)

**最小配置** (2 个 ECS 任务, db.t3.medium):
```
ECS Fargate:
  - 2 tasks × 4 vCPU × 8GB × 730 hours
  - CPU: 2 × 4 × $0.04048 × 730 = $236
  - Memory: 2 × 8 × $0.004445 × 730 = $52
  - 小计: ~$288/月

RDS PostgreSQL:
  - db.t3.medium Multi-AZ: ~$131/月
  - Storage 100GB GP3: ~$23/月
  - Backup 100GB: ~$10/月
  - 小计: ~$164/月

ALB:
  - 固定成本: ~$22/月
  - 数据处理 (假设 100GB): ~$1/月
  - 小计: ~$23/月

其他:
  - ECR 存储: ~$1/月
  - CloudWatch Logs: ~$5/月
  - Secrets Manager: ~$1/月
  - Route53 (可选): ~$0.5/月

总计: ~$482/月
```

**生产配置** (平均 4 个任务, db.r6g.xlarge):
```
ECS Fargate: ~$576/月
RDS PostgreSQL: ~$450/月
ALB: ~$23/月
其他: ~$20/月

总计: ~$1,069/月
```

### 成本优化建议

1. **使用 Savings Plans**
   - ECS Fargate: 节省最多 50%
   - RDS: 节省最多 72%

2. **合理配置自动扩展**
   ```hcl
   # 降低最小容量（非高峰期）
   ecs_min_capacity = 1

   # 使用定时扩展
   enable_scheduled_scaling = true
   ```

3. **优化数据库**
   ```hcl
   # 开发环境使用单 AZ
   db_multi_az = false

   # 使用更小的实例
   db_instance_class = "db.t3.small"
   ```

4. **减少日志保留时间**
   ```hcl
   cloudwatch_log_retention_days = 3
   db_backup_retention_period = 3
   ```

## 🔐 安全最佳实践

### 1. 使用 Secrets Manager

所有敏感信息都存储在 AWS Secrets Manager:
- ✅ 数据库密码自动生成
- ✅ API Keys 加密存储
- ✅ 自动轮换支持

### 2. 网络隔离

- ✅ ECS 任务在私有子网
- ✅ RDS 数据库不可公网访问
- ✅ 安全组最小化权限

### 3. 启用加密

- ✅ RDS 存储加密
- ✅ Secrets Manager 加密
- ✅ HTTPS 传输加密

### 4. 审计和监控

```bash
# 启用 CloudTrail
aws cloudtrail create-trail \
  --name litellm-audit \
  --s3-bucket-name litellm-audit-logs

# 启用 AWS Config
aws configservice put-configuration-recorder \
  --configuration-recorder name=litellm-config,roleARN=arn:aws:iam::...

# 启用 GuardDuty
aws guardduty create-detector --enable
```

## 📚 更多资源

- [LiteLLM 官方文档](https://docs.litellm.ai)
- [AWS ECS 最佳实践](https://docs.aws.amazon.com/AmazonECS/latest/bestpracticesguide/intro.html)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

## 🤝 支持

遇到问题？

1. 查看 [故障排查](#故障排查) 部分
2. 查看 CloudWatch 日志
3. 提交 Issue 到 GitHub

---

**部署成功后的后续步骤:**

1. ✅ 配置监控告警
2. ✅ 设置备份策略
3. ✅ 配置 WAF (可选)
4. ✅ 实施成本监控
5. ✅ 文档化运维流程
