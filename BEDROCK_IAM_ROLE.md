# 使用 IAM Role 访问 Bedrock（推荐方案）

## 🎯 为什么使用 IAM Role？

### 安全优势

| 方面 | AK/SK 方式 | IAM Role 方式 |
|-----|-----------|--------------|
| **凭证泄露风险** | 高 - 长期有效 | 低 - 临时凭证（6小时） |
| **轮换** | 需要手动轮换 | 自动轮换 |
| **存储** | 需要 Secrets Manager | 无需存储 |
| **被入侵影响** | 凭证可被窃取 | 只能在 ECS 内使用 |
| **审计** | 基于用户 | 基于角色（更清晰） |
| **遵循 AWS 最佳实践** | ❌ | ✅ |

---

## 📋 实施步骤

### 第一步：创建 Bedrock IAM Role

创建文件 `bedrock-role.tf`:

```hcl
# bedrock-role.tf

# ============================================
# IAM Role for Bedrock Access (推荐方案)
# ============================================

# 创建 Bedrock 访问角色
resource "aws_iam_role" "bedrock_access_role" {
  name = "${var.project_name}-bedrock-access-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-bedrock-role"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# Bedrock 访问策略
resource "aws_iam_role_policy" "bedrock_access_policy" {
  name = "${var.project_name}-bedrock-policy"
  role = aws_iam_role.bedrock_access_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        Resource = [
          "arn:aws:bedrock:*::foundation-model/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "bedrock:ListFoundationModels",
          "bedrock:GetFoundationModel"
        ]
        Resource = "*"
      }
    ]
  })
}

# 可选：添加其他 AWS 服务权限
# 如果需要访问 S3、DynamoDB 等
resource "aws_iam_role_policy" "additional_permissions" {
  count = var.enable_additional_aws_services ? 1 : 0

  name = "${var.project_name}-additional-permissions"
  role = aws_iam_role.bedrock_access_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = "arn:aws:s3:::${var.litellm_bucket_name}/*"
      }
    ]
  })
}
```

---

### 第二步：更新 ECS Task Role

修改 `iam.tf`，将 Bedrock Role 附加到 ECS Task Role：

```hcl
# iam.tf

# 方式 1: 直接使用 Bedrock Role 作为 Task Role
resource "aws_ecs_task_definition" "litellm_task" {
  # ...
  task_role_arn = aws_iam_role.bedrock_access_role.arn
  # ...
}

# 或方式 2: 给现有 Task Role 添加 Bedrock 权限
resource "aws_iam_role_policy_attachment" "ecs_task_bedrock_access" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonBedrockFullAccess"
}
```

**推荐方式 2**（更灵活）：

```hcl
# iam.tf

# 给 ECS Task Role 添加 Bedrock 策略
resource "aws_iam_role_policy" "ecs_task_bedrock_policy" {
  name = "${var.project_name}-bedrock-access"
  role = aws_iam_role.ecs_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        Resource = "arn:aws:bedrock:*::foundation-model/*"
      },
      {
        Effect = "Allow"
        Action = [
          "bedrock:ListFoundationModels",
          "bedrock:GetFoundationModel"
        ]
        Resource = "*"
      }
    ]
  })
}
```

---

### 第三步：更新 config.yaml

**关键变化：移除 AK/SK 配置**

```yaml
# config.yaml

model_list:
  # ✅ 使用 IAM Role - 无需指定凭证
  - model_name: claude-bedrock
    litellm_params:
      model: bedrock/anthropic.claude-3-5-sonnet-20240620-v1:0
      # ❌ 删除这两行
      # aws_access_key_id: os.environ/AWS_ACCESS_KEY_ID
      # aws_secret_access_key: os.environ/AWS_SECRET_ACCESS_KEY
      # ✅ 只需要指定区域
      aws_region_name: us-east-1

  # 多个 Bedrock 模型
  - model_name: claude-3-sonnet-bedrock
    litellm_params:
      model: bedrock/anthropic.claude-3-sonnet-20240229-v1:0
      aws_region_name: us-east-1

  - model_name: claude-3-haiku-bedrock
    litellm_params:
      model: bedrock/anthropic.claude-3-haiku-20240307-v1:0
      aws_region_name: us-east-1
```

**工作原理：**
- LiteLLM 会自动检测到运行在 ECS 上
- 自动使用 Task Role 的临时凭证
- 无需任何环境变量

---

### 第四步：移除 AK/SK 配置

编辑 `terraform.tfvars`，**删除** Bedrock 凭证：

```hcl
# terraform.tfvars

# ❌ 删除这两行（不再需要）
# aws_access_key_id     = "AKIA..."
# aws_secret_access_key = "wJalr..."

# 其他配置保持不变
litellm_master_key = "sk-..."
openai_api_key     = "sk-proj-..."
```

---

### 第五步：更新 taskdefinition.tf

确保不注入 AWS 凭证到环境变量：

```hcl
# taskdefinition.tf

resource "aws_ecs_task_definition" "litellm_task" {
  # ...

  # 确保使用正确的 Task Role
  task_role_arn = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([{
    # ...

    # 环境变量中移除 AWS 凭证
    environment = [
      # ... 其他环境变量
      {
        name  = "AWS_REGION"
        value = var.aws_region
      }
      # ❌ 不要包含:
      # AWS_ACCESS_KEY_ID
      # AWS_SECRET_ACCESS_KEY
    ]

    # Secrets 中也移除 AWS 凭证
    secrets = [
      # OpenAI, Anthropic 等其他 API Keys
      # ❌ 不要包含 AWS 凭证
    ]
  }])
}
```

---

### 第六步：部署

```bash
# 1. 应用 Terraform 变更
terraform apply

# 2. 重新构建 Docker 镜像（使用新的 config.yaml）
./build.sh

# 3. 验证部署
aws ecs describe-tasks \
  --cluster litellm-ecs-cluster \
  --tasks $(aws ecs list-tasks --cluster litellm-ecs-cluster --query 'taskArns[0]' --output text) \
  --query 'tasks[0].taskRoleArn'

# 应该看到 Task Role ARN
```

---

## ✅ 验证 IAM Role 生效

### 测试 1: 检查容器内没有静态凭证

```bash
# 进入容器（如果启用了 ECS Exec）
aws ecs execute-command \
  --cluster litellm-ecs-cluster \
  --task <task-id> \
  --container litellm-container \
  --interactive \
  --command "/bin/bash"

# 在容器内检查
echo $AWS_ACCESS_KEY_ID
# 应该是空的，或者是以 ASIA 开头的临时凭证

echo $AWS_SECRET_ACCESS_KEY
# 应该是空的，或者是临时凭证

# 检查临时凭证（来自 ECS Task Role）
curl 169.254.170.2$AWS_CONTAINER_CREDENTIALS_RELATIVE_URI
# 应该返回临时凭证（自动轮换）
```

### 测试 2: 调用 Bedrock API

```bash
curl https://your-litellm.com/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer sk-your-master-key" \
  -d '{
    "model": "claude-bedrock",
    "messages": [{"role": "user", "content": "Test IAM Role"}]
  }'

# 应该正常返回响应
```

### 测试 3: 查看 CloudTrail 审计

```bash
# 查看 Bedrock API 调用记录
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=InvokeModel \
  --max-results 10

# 应该看到 Principal 是 ECS Task Role，而不是 IAM 用户
```

---

## 🔍 故障排查

### 问题 1: "Access Denied" 错误

**症状:**
```json
{
  "error": {
    "message": "User: arn:aws:sts::123456789012:assumed-role/litellm-ecs-task-role/abc is not authorized to perform: bedrock:InvokeModel"
  }
}
```

**解决方案:**

```bash
# 1. 检查 Task Role 是否有 Bedrock 权限
aws iam list-role-policies --role-name litellm-ecs-task-role

# 2. 检查策略内容
aws iam get-role-policy \
  --role-name litellm-ecs-task-role \
  --policy-name litellm-bedrock-access

# 3. 如果没有权限，重新应用 Terraform
terraform apply
```

---

### 问题 2: config.yaml 中还保留了 AK/SK 配置

**症状:**
LiteLLM 仍然尝试使用环境变量中的凭证，但这些凭证已被删除。

**解决方案:**

```yaml
# config.yaml

# ❌ 错误配置
- model_name: claude-bedrock
  litellm_params:
    model: bedrock/anthropic.claude-3-5-sonnet-20240620-v1:0
    aws_access_key_id: os.environ/AWS_ACCESS_KEY_ID      # 删除
    aws_secret_access_key: os.environ/AWS_SECRET_ACCESS_KEY  # 删除
    aws_region_name: us-east-1

# ✅ 正确配置
- model_name: claude-bedrock
  litellm_params:
    model: bedrock/anthropic.claude-3-5-sonnet-20240629-v1:0
    aws_region_name: us-east-1  # 只需要区域
```

重新构建:
```bash
./build.sh
```

---

### 问题 3: 临时凭证过期

**症状:**
虽然使用 IAM Role，但仍然看到凭证过期错误。

**原因:**
ECS Task Role 的临时凭证每 6 小时自动轮换。LiteLLM 应该自动刷新。

**解决方案:**

如果 LiteLLM 没有自动刷新，重启服务:
```bash
aws ecs update-service \
  --cluster litellm-ecs-cluster \
  --service litellm-service \
  --force-new-deployment
```

---

## 🎯 完整迁移清单

迁移到 IAM Role 前确认：

- [ ] 创建了 Bedrock IAM 策略（`iam.tf`）
- [ ] 给 ECS Task Role 附加了 Bedrock 权限
- [ ] 更新了 `config.yaml`（移除 AK/SK 配置）
- [ ] 从 `terraform.tfvars` 删除了 AK/SK
- [ ] 运行了 `terraform apply`
- [ ] 重新构建了 Docker 镜像（`./build.sh`）
- [ ] 测试了 Bedrock API 调用
- [ ] 验证了 CloudTrail 显示正确的 Role
- [ ] 删除了旧的 IAM 用户（可选）

---

## 🔐 清理旧的 IAM 用户（可选）

如果完全迁移到 IAM Role，可以删除旧的 IAM 用户：

```bash
# 1. 禁用访问密钥
aws iam list-access-keys --user-name litellm-bedrock-user
aws iam update-access-key \
  --access-key-id AKIA... \
  --status Inactive \
  --user-name litellm-bedrock-user

# 2. 删除访问密钥
aws iam delete-access-key \
  --access-key-id AKIA... \
  --user-name litellm-bedrock-user

# 3. 分离策略
aws iam detach-user-policy \
  --user-name litellm-bedrock-user \
  --policy-arn arn:aws:iam::aws:policy/AmazonBedrockFullAccess

# 4. 删除用户
aws iam delete-user --user-name litellm-bedrock-user

# 5. 从 Secrets Manager 删除凭证（可选）
aws secretsmanager delete-secret \
  --secret-id litellm/aws_access_key_id \
  --force-delete-without-recovery

aws secretsmanager delete-secret \
  --secret-id litellm/aws_secret_access_key \
  --force-delete-without-recovery
```

---

## 💰 成本对比

| 方案 | Secrets Manager | IAM 成本 |
|-----|----------------|---------|
| **AK/SK** | $0.80/月（2个secrets） | 免费 |
| **IAM Role** | 免费 ✅ | 免费 ✅ |

**节省**: $0.80/月（虽然少，但更安全）

---

## 📊 安全对比

### 供应链攻击场景

**AK/SK 方式（当前）:**
```
恶意代码植入 LiteLLM
    ↓
读取环境变量
    ↓
获取 AWS_ACCESS_KEY_ID 和 AWS_SECRET_ACCESS_KEY
    ↓
发送到攻击者服务器
    ↓
攻击者可以随时随地使用这些凭证 ❌
```

**IAM Role 方式（推荐）:**
```
恶意代码植入 LiteLLM
    ↓
尝试读取环境变量
    ↓
没有找到静态凭证 ✅
    ↓
只能访问临时凭证（6小时有效期）
    ↓
且只能在 ECS 任务内使用
    ↓
CloudTrail 完整审计日志 ✅
```

---

## 🎓 最佳实践总结

### ✅ 推荐做法

1. **优先使用 IAM Role**
   - 无需管理密钥
   - 自动轮换
   - 最小权限

2. **限制 Role 权限**
   ```json
   {
     "Resource": "arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-*"
   }
   ```
   而不是 `"Resource": "*"`

3. **启用 CloudTrail**
   - 记录所有 Bedrock API 调用
   - 设置异常告警

4. **定期审计**
   ```bash
   # 每周检查 Bedrock 使用情况
   aws cloudtrail lookup-events \
     --lookup-attributes AttributeKey=EventName,AttributeValue=InvokeModel
   ```

### ❌ 避免做法

1. ❌ 使用长期 AK/SK
2. ❌ 给予过多权限（如 `*` resource）
3. ❌ 不监控 API 调用
4. ❌ 使用 Root 账户凭证

---

## 🚀 快速迁移命令

```bash
# 1. 更新 iam.tf
cat >> iam.tf <<'EOF'

# Bedrock access for ECS Task Role
resource "aws_iam_role_policy" "ecs_task_bedrock_policy" {
  name = "litellm-bedrock-access"
  role = aws_iam_role.ecs_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream"
      ]
      Resource = "arn:aws:bedrock:*::foundation-model/*"
    }]
  })
}
EOF

# 2. 更新 config.yaml
vim config.yaml
# 删除 aws_access_key_id 和 aws_secret_access_key 行

# 3. 更新 terraform.tfvars
vim terraform.tfvars
# 删除 aws_access_key_id 和 aws_secret_access_key 行

# 4. 部署
terraform apply
./build.sh

# 5. 测试
curl https://your-litellm.com/v1/chat/completions \
  -H "Authorization: Bearer sk-your-key" \
  -d '{"model":"claude-bedrock","messages":[{"role":"user","content":"test"}]}'
```

---

**迁移到 IAM Role 后，你的 Bedrock 访问将更加安全！** 🎉

即使 LiteLLM 被入侵，攻击者也无法窃取长期有效的凭证。
