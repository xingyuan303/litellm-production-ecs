# 🚀 LiteLLM 快速开始指南

5 分钟快速部署 LiteLLM 到 AWS！

## 📋 准备清单

- [ ] AWS 账户
- [ ] AWS CLI 已配置
- [ ] Terraform 已安装 (>= 1.0)
- [ ] Docker 已安装
- [ ] 至少一个 LLM API Key (OpenAI/Anthropic 等)

## 🎯 快速部署 (5 步)

### 1️⃣ 配置 AWS 凭证

```bash
aws configure --profile litellm-prod
# 输入: Access Key ID, Secret Key, Region (us-east-1)
```

### 2️⃣ 创建配置文件

```bash
cd litellm-production-ecs

# 复制配置模板
cp terraform.tfvars.example terraform.tfvars

# 编辑配置 (最小化)
cat > terraform.tfvars <<'EOF'
project_name = "litellm"
aws_region   = "us-east-1"

# 生成安全密钥
litellm_master_key = "sk-your-secure-key-here"
litellm_salt_key   = "your-salt-key-here"

# 添加至少一个 API Key
openai_api_key = "sk-proj-..."
# anthropic_api_key = "sk-ant-..."

# 数据库配置
db_instance_class = "db.t3.medium"
db_multi_az       = true

# 暂时禁用 HTTPS (快速测试)
enable_https = false
EOF
```

**💡 生成安全密钥:**
```bash
# Master Key
echo "sk-$(openssl rand -hex 16)"

# Salt Key
openssl rand -hex 32
```

### 3️⃣ 部署基础设施

```bash
# 初始化 Terraform
terraform init

# 预览要创建的资源
terraform plan

# 部署 (需要 15-20 分钟)
terraform apply
# 输入: yes
```

**等待创建:**
- ✅ ECS 集群
- ✅ RDS 数据库
- ✅ ALB 负载均衡器
- ✅ 安全组和角色

### 4️⃣ 构建并部署 Docker 镜像

```bash
# 一键构建和部署
./build.sh

# 或手动执行:
# 1. 登录 ECR
ECR_URL=$(terraform output -raw ecr_repository_url)
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin $ECR_URL

# 2. 构建镜像
docker buildx build --platform linux/amd64 -t litellm:latest .

# 3. 推送镜像
docker tag litellm:latest $ECR_URL:latest
docker push $ECR_URL:latest

# 4. 更新 ECS 服务
aws ecs update-service \
  --cluster $(terraform output -raw ecs_cluster_name) \
  --service $(terraform output -raw ecs_service_name) \
  --force-new-deployment \
  --region us-east-1
```

### 5️⃣ 验证部署

```bash
# 等待服务启动 (2-3 分钟)
watch -n 5 'aws ecs describe-services \
  --cluster litellm-ecs-cluster \
  --services litellm-service \
  --query "services[0].runningCount"'

# 获取访问 URL
ALB_URL=$(terraform output -raw alb_url_http)
echo $ALB_URL

# 测试健康检查
curl $ALB_URL/health
# 预期: {"status": "healthy"}

# 测试 API
curl $ALB_URL/v1/models \
  -H "Authorization: Bearer sk-your-secure-key-here"

# 测试聊天
curl $ALB_URL/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer sk-your-secure-key-here" \
  -d '{
    "model": "gpt-4",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

## ✅ 成功！

你现在有了一个运行中的 LiteLLM 实例：

- 🌐 访问地址: `http://<alb-dns>`
- 🔑 API Key: `terraform.tfvars` 中配置的 master key
- 📊 监控: CloudWatch Logs `/ecs/litellm`
- 🗄️ 数据库: RDS PostgreSQL (Multi-AZ)

## 🎨 下一步 (可选)

### 添加 HTTPS 和自定义域名

```bash
# 1. 编辑 terraform.tfvars
cat >> terraform.tfvars <<'EOF'

# 启用 HTTPS
enable_https      = true
domain_name       = "example.com"
litellm_subdomain = "litellm.example.com"
EOF

# 2. 重新部署
terraform apply

# 3. 等待 DNS 生效 (10-30 分钟)
# 4. 访问 https://litellm.example.com
```

### 配置更多模型

编辑 `config.yaml`:

```yaml
model_list:
  # 添加更多模型
  - model_name: claude-opus-4
    litellm_params:
      model: anthropic/claude-opus-4-20250514
      api_key: os.environ/ANTHROPIC_API_KEY

  - model_name: gpt-3.5-turbo
    litellm_params:
      model: openai/gpt-3.5-turbo
      api_key: os.environ/OPENAI_API_KEY
```

重新构建:
```bash
./build.sh
```

### 调整自动扩展

```bash
# 编辑 terraform.tfvars
cat >> terraform.tfvars <<'EOF'

# 扩展配置
ecs_min_capacity = 2
ecs_max_capacity = 20
cpu_target_value = 70
EOF

# 应用变更
terraform apply
```

### 设置监控告警

```bash
# 1. 创建 SNS Topic
aws sns create-topic --name litellm-alerts

# 2. 订阅邮箱
aws sns subscribe \
  --topic-arn arn:aws:sns:us-east-1:ACCOUNT_ID:litellm-alerts \
  --protocol email \
  --notification-endpoint your-email@example.com

# 3. 确认订阅邮件

# 4. 更新配置
cat >> terraform.tfvars <<'EOF'
alarm_sns_topic_arn = "arn:aws:sns:us-east-1:ACCOUNT_ID:litellm-alerts"
EOF

# 5. 应用
terraform apply
```

## 🔧 常用命令

```bash
# 查看服务状态
aws ecs describe-services \
  --cluster litellm-ecs-cluster \
  --services litellm-service

# 查看实时日志
aws logs tail /ecs/litellm --follow

# 手动扩展
aws ecs update-service \
  --cluster litellm-ecs-cluster \
  --service litellm-service \
  --desired-count 5

# 重新部署 (更新镜像后)
./build.sh

# 获取数据库密码
aws secretsmanager get-secret-value \
  --secret-id litellm/db_password \
  --query SecretString \
  --output text
```

## 📊 监控

**CloudWatch 控制台:**
- ECS: https://console.aws.amazon.com/ecs/
- RDS: https://console.aws.amazon.com/rds/
- Logs: https://console.aws.amazon.com/cloudwatch/

**CLI 监控:**
```bash
# CPU 使用率
aws cloudwatch get-metric-statistics \
  --namespace AWS/ECS \
  --metric-name CPUUtilization \
  --dimensions Name=ServiceName,Value=litellm-service \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average

# 内存使用率
aws cloudwatch get-metric-statistics \
  --namespace AWS/ECS \
  --metric-name MemoryUtilization \
  --dimensions Name=ServiceName,Value=litellm-service \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average
```

## 🔍 故障排查

### 问题: ECS 任务无法启动

```bash
# 查看任务失败原因
aws ecs describe-tasks \
  --cluster litellm-ecs-cluster \
  --tasks $(aws ecs list-tasks --cluster litellm-ecs-cluster --query 'taskArns[0]' --output text)

# 查看日志
aws logs tail /ecs/litellm --follow
```

### 问题: 无法访问 ALB

```bash
# 检查目标健康
aws elbv2 describe-target-health \
  --target-group-arn $(aws elbv2 describe-target-groups --names litellm-tg --query 'TargetGroups[0].TargetGroupArn' --output text)

# 检查安全组
aws ec2 describe-security-groups \
  --group-ids $(terraform output -raw alb_security_group_id)
```

### 问题: 数据库连接失败

```bash
# 检查 RDS 状态
aws rds describe-db-instances --db-instance-identifier litellm-db

# 测试连接
psql "$(terraform output -raw database_url)"
```

## 🗑️ 清理资源

**⚠️ 警告: 这会删除所有资源，包括数据库！**

```bash
# 销毁所有资源
terraform destroy

# 确认输入: yes

# 手动删除 ECR 镜像 (如果需要)
aws ecr delete-repository --repository-name litellm-dev --force
```

## 💰 成本

**最小配置估算 (~$482/月):**
- ECS Fargate (2 tasks): ~$288/月
- RDS db.t3.medium: ~$164/月
- ALB: ~$23/月
- 其他: ~$7/月

**优化建议:**
- 使用 AWS Savings Plans: 节省 50-70%
- 开发环境: 单 AZ + 更小实例
- 定时扩展: 非工作时间缩减实例

## 📚 更多文档

- **完整部署指南**: [DEPLOYMENT.md](./DEPLOYMENT.md)
- **README**: [README.md](./README.md)

## 🆘 获取帮助

遇到问题？

1. 查看 [DEPLOYMENT.md](./DEPLOYMENT.md) 中的故障排查部分
2. 查看 CloudWatch Logs
3. 提交 Issue

---

**祝您使用愉快！** 🎉
