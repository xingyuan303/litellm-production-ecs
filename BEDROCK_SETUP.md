# AWS Bedrock 配置指南

本文档说明如何配置 LiteLLM 调用 AWS Bedrock 模型。

## 📋 配置流程概览

```
1. 在 terraform.tfvars 中配置 AK/SK
          ↓
2. Terraform 存储到 Secrets Manager
          ↓
3. ECS 任务启动时注入环境变量
          ↓
4. config.yaml 中配置 Bedrock 模型
          ↓
5. LiteLLM 使用环境变量调用 Bedrock
```

---

## 🔧 **第一步：配置 Terraform 变量**

编辑 `terraform.tfvars` 文件，添加 Bedrock 凭证：

```hcl
# terraform.tfvars

# 其他配置...
litellm_master_key = "sk-..."
openai_api_key     = "sk-proj-..."

# 添加 AWS Bedrock 凭证
aws_access_key_id     = "AKIA..."           # 你的 Access Key ID
aws_secret_access_key = "wJalrXUtn..."     # 你的 Secret Access Key
```

### ⚠️ **重要：Bedrock 专用凭证**

**推荐创建专门用于 Bedrock 的 IAM 用户，不要用部署 ECS 的凭证！**

原因：
- ✅ 最小权限原则
- ✅ 便于审计和成本追踪
- ✅ 更安全（泄露影响范围小）

---

## 🔑 **创建 Bedrock IAM 用户（推荐）**

### 步骤 1: 创建 IAM 用户

```bash
# 创建专门用于 Bedrock 的用户
aws iam create-user --user-name litellm-bedrock-user

# 创建访问密钥
aws iam create-access-key --user-name litellm-bedrock-user

# 输出示例:
# {
#     "AccessKey": {
#         "AccessKeyId": "AKIAIOSFODNN7EXAMPLE",
#         "SecretAccessKey": "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
#         "Status": "Active"
#     }
# }

# ⚠️ 保存这些凭证！只会显示一次！
```

### 步骤 2: 附加 Bedrock 权限

**方式 1: 使用 AWS 托管策略（简单）**

```bash
# 附加 Bedrock 完全访问权限
aws iam attach-user-policy \
  --user-name litellm-bedrock-user \
  --policy-arn arn:aws:iam::aws:policy/AmazonBedrockFullAccess
```

**方式 2: 自定义策略（推荐，最小权限）**

创建文件 `bedrock-policy.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "BedrockInvokeModel",
      "Effect": "Allow",
      "Action": [
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream"
      ],
      "Resource": [
        "arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-v2",
        "arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-v2:1",
        "arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-3-sonnet-20240229-v1:0",
        "arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-3-5-sonnet-20240620-v1:0",
        "arn:aws:bedrock:*::foundation-model/*"
      ]
    },
    {
      "Sid": "BedrockListModels",
      "Effect": "Allow",
      "Action": [
        "bedrock:ListFoundationModels",
        "bedrock:GetFoundationModel"
      ],
      "Resource": "*"
    }
  ]
}
```

应用策略:

```bash
# 创建策略
aws iam create-policy \
  --policy-name LiteLLMBedrockPolicy \
  --policy-document file://bedrock-policy.json

# 获取策略 ARN（从上一步输出中获取）
POLICY_ARN="arn:aws:iam::YOUR-ACCOUNT-ID:policy/LiteLLMBedrockPolicy"

# 附加到用户
aws iam attach-user-policy \
  --user-name litellm-bedrock-user \
  --policy-arn $POLICY_ARN
```

---

## 🗄️ **第二步：Terraform 自动存储到 Secrets Manager**

当你配置了 `aws_access_key_id` 和 `aws_secret_access_key` 后，运行：

```bash
terraform apply
```

Terraform 会自动：

1. ✅ 创建 Secrets Manager secrets:
   - `litellm/aws_access_key_id`
   - `litellm/aws_secret_access_key`

2. ✅ 加密存储凭证

3. ✅ 配置 ECS 任务定义注入环境变量

**验证存储成功:**

```bash
# 查看 Access Key ID
aws secretsmanager get-secret-value \
  --secret-id litellm/aws_access_key_id \
  --query SecretString \
  --output text

# 查看 Secret Access Key
aws secretsmanager get-secret-value \
  --secret-id litellm/aws_secret_access_key \
  --query SecretString \
  --output text
```

---

## 📝 **第三步：配置 config.yaml 使用 Bedrock**

编辑 `config.yaml` 文件，取消注释 Bedrock 配置：

```yaml
# config.yaml

model_list:
  # 现有模型...
  - model_name: gpt-4
    litellm_params:
      model: openai/gpt-4
      api_key: os.environ/OPENAI_API_KEY

  # ✅ 添加 Bedrock Claude V2
  - model_name: claude-bedrock-v2
    litellm_params:
      model: bedrock/anthropic.claude-v2
      aws_access_key_id: os.environ/AWS_ACCESS_KEY_ID
      aws_secret_access_key: os.environ/AWS_SECRET_ACCESS_KEY
      aws_region_name: us-east-1

  # ✅ 添加 Bedrock Claude 3 Sonnet
  - model_name: claude-3-sonnet-bedrock
    litellm_params:
      model: bedrock/anthropic.claude-3-sonnet-20240229-v1:0
      aws_access_key_id: os.environ/AWS_ACCESS_KEY_ID
      aws_secret_access_key: os.environ/AWS_SECRET_ACCESS_KEY
      aws_region_name: us-east-1

  # ✅ 添加 Bedrock Claude 3.5 Sonnet
  - model_name: claude-3-5-sonnet-bedrock
    litellm_params:
      model: bedrock/anthropic.claude-3-5-sonnet-20240620-v1:0
      aws_access_key_id: os.environ/AWS_ACCESS_KEY_ID
      aws_secret_access_key: os.environ/AWS_SECRET_ACCESS_KEY
      aws_region_name: us-east-1

  # ✅ Amazon Titan Text
  - model_name: titan-text-express
    litellm_params:
      model: bedrock/amazon.titan-text-express-v1
      aws_access_key_id: os.environ/AWS_ACCESS_KEY_ID
      aws_secret_access_key: os.environ/AWS_SECRET_ACCESS_KEY
      aws_region_name: us-east-1

  # ✅ AI21 Jamba
  - model_name: jamba-instruct
    litellm_params:
      model: bedrock/ai21.jamba-instruct-v1:0
      aws_access_key_id: os.environ/AWS_ACCESS_KEY_ID
      aws_secret_access_key: os.environ/AWS_SECRET_ACCESS_KEY
      aws_region_name: us-east-1
```

### 📍 **重要说明**

**环境变量引用:**
```yaml
aws_access_key_id: os.environ/AWS_ACCESS_KEY_ID
aws_secret_access_key: os.environ/AWS_SECRET_ACCESS_KEY
```

这些环境变量由 ECS 任务自动注入，来源于 Secrets Manager。

**不要写成:**
```yaml
# ❌ 错误：不要硬编码
aws_access_key_id: "AKIAIOSFODNN7EXAMPLE"
aws_secret_access_key: "wJalrXUtn..."

# ✅ 正确：使用环境变量
aws_access_key_id: os.environ/AWS_ACCESS_KEY_ID
```

---

## 🐳 **第四步：重新构建和部署**

修改 `config.yaml` 后，需要重新构建 Docker 镜像：

```bash
# 重新构建并推送
./build.sh

# 或手动执行
docker buildx build --platform linux/amd64 -t litellm:latest .
docker tag litellm:latest $(terraform output -raw ecr_repository_url):latest
docker push $(terraform output -raw ecr_repository_url):latest

# 强制 ECS 更新
aws ecs update-service \
  --cluster litellm-ecs-cluster \
  --service litellm-service \
  --force-new-deployment \
  --region us-east-1
```

---

## 🧪 **第五步：测试 Bedrock 模型**

### 测试 1: 列出可用模型

```bash
curl https://your-litellm-url.com/v1/models \
  -H "Authorization: Bearer sk-your-master-key"

# 应该看到 Bedrock 模型:
# {
#   "data": [
#     {"id": "claude-bedrock-v2", ...},
#     {"id": "claude-3-sonnet-bedrock", ...},
#     ...
#   ]
# }
```

### 测试 2: 调用 Bedrock Claude

```bash
curl https://your-litellm-url.com/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer sk-your-master-key" \
  -d '{
    "model": "claude-3-sonnet-bedrock",
    "messages": [
      {"role": "user", "content": "Hello from Bedrock!"}
    ]
  }'

# 成功响应:
# {
#   "id": "chatcmpl-...",
#   "object": "chat.completion",
#   "model": "claude-3-sonnet-bedrock",
#   "choices": [
#     {
#       "message": {
#         "role": "assistant",
#         "content": "Hello! ..."
#       }
#     }
#   ]
# }
```

### 测试 3: 查看日志

```bash
# 查看 LiteLLM 日志确认 Bedrock 调用
aws logs tail /ecs/litellm --follow --filter-pattern "bedrock"
```

---

## 🌍 **支持的 Bedrock 区域**

根据你的 Bedrock 可用区域配置 `aws_region_name`:

| 区域 | 代码 | Bedrock 可用性 |
|-----|------|---------------|
| 美国东部（弗吉尼亚北部） | `us-east-1` | ✅ 完全支持 |
| 美国西部（俄勒冈） | `us-west-2` | ✅ 完全支持 |
| 亚太地区（新加坡） | `ap-southeast-1` | ✅ 支持 |
| 欧洲（法兰克福） | `eu-central-1` | ✅ 支持 |
| 亚太地区（东京） | `ap-northeast-1` | ✅ 支持 |

**检查可用区域:**
```bash
aws bedrock list-foundation-models --region us-east-1
```

---

## 📊 **Bedrock 模型 ID 对照表**

| LiteLLM 模型名 | Bedrock 模型 ID | 用途 |
|---------------|----------------|------|
| `bedrock/anthropic.claude-v2` | Claude V2 | 通用对话 |
| `bedrock/anthropic.claude-v2:1` | Claude V2.1 | 改进版 |
| `bedrock/anthropic.claude-3-sonnet-20240229-v1:0` | Claude 3 Sonnet | 高性能 |
| `bedrock/anthropic.claude-3-5-sonnet-20240620-v1:0` | Claude 3.5 Sonnet | 最新最强 |
| `bedrock/anthropic.claude-3-haiku-20240307-v1:0` | Claude 3 Haiku | 快速低成本 |
| `bedrock/anthropic.claude-3-opus-20240229-v1:0` | Claude 3 Opus | 最强性能 |
| `bedrock/amazon.titan-text-express-v1` | Titan Text Express | Amazon 模型 |
| `bedrock/ai21.jamba-instruct-v1:0` | AI21 Jamba | 长上下文 |
| `bedrock/cohere.command-r-plus-v1:0` | Cohere Command R+ | RAG 优化 |
| `bedrock/meta.llama3-70b-instruct-v1:0` | Llama 3 70B | 开源模型 |

**完整列表:**
```bash
# 查看所有可用模型
aws bedrock list-foundation-models \
  --region us-east-1 \
  --query 'modelSummaries[*].[modelId,modelName]' \
  --output table
```

---

## 💰 **Bedrock 定价**

### 按需定价（输入/输出 tokens）

| 模型 | 输入成本 | 输出成本 |
|-----|---------|---------|
| Claude 3.5 Sonnet | $3/MTok | $15/MTok |
| Claude 3 Sonnet | $3/MTok | $15/MTok |
| Claude 3 Haiku | $0.25/MTok | $1.25/MTok |
| Claude V2 | $8/MTok | $24/MTok |
| Titan Text Express | $0.2/MTok | $0.6/MTok |

MTok = 百万 tokens

**成本估算示例:**
```
Claude 3.5 Sonnet:
- 每天 1000 次请求
- 平均 500 tokens 输入 + 1000 tokens 输出
- 成本 = (0.5M × $3 + 1M × $15) × 30 = $495/月
```

---

## 🔍 **故障排查**

### 问题 1: "Missing AWS credentials"

**症状:**
```json
{
  "error": {
    "message": "Missing AWS credentials"
  }
}
```

**排查步骤:**

```bash
# 1. 检查 Secrets Manager 中是否有凭证
aws secretsmanager list-secrets \
  --query "SecretList[?contains(Name, 'litellm/aws')]"

# 2. 检查 ECS 任务定义
aws ecs describe-task-definition \
  --task-definition litellm-task \
  --query 'taskDefinition.containerDefinitions[0].secrets'

# 3. 检查运行中的任务环境变量
aws ecs describe-tasks \
  --cluster litellm-ecs-cluster \
  --tasks $(aws ecs list-tasks --cluster litellm-ecs-cluster --query 'taskArns[0]' --output text)
```

**解决方案:**
```bash
# 确保在 terraform.tfvars 中配置了:
aws_access_key_id     = "AKIA..."
aws_secret_access_key = "wJalr..."

# 重新部署
terraform apply
./build.sh
```

---

### 问题 2: "Access Denied" 或权限错误

**症状:**
```json
{
  "error": {
    "message": "User: arn:aws:iam::123456789012:user/litellm-bedrock-user is not authorized to perform: bedrock:InvokeModel"
  }
}
```

**解决方案:**

```bash
# 检查用户权限
aws iam list-attached-user-policies \
  --user-name litellm-bedrock-user

# 如果没有权限，附加策略
aws iam attach-user-policy \
  --user-name litellm-bedrock-user \
  --policy-arn arn:aws:iam::aws:policy/AmazonBedrockFullAccess
```

---

### 问题 3: 模型不可用

**症状:**
```json
{
  "error": {
    "message": "The requested model is not available in this region"
  }
}
```

**解决方案:**

```bash
# 1. 检查模型在你的区域是否可用
aws bedrock list-foundation-models \
  --region us-east-1 \
  --query 'modelSummaries[?contains(modelId, `claude`)]'

# 2. 如果不可用，切换到支持的区域
# 在 config.yaml 中修改:
aws_region_name: us-west-2  # 改为支持的区域
```

---

### 问题 4: 需要申请模型访问权限

某些 Bedrock 模型需要先申请访问权限。

**检查访问权限:**
```bash
# 访问 AWS Bedrock 控制台
https://console.aws.amazon.com/bedrock/

# 导航到: Model access
# 为需要的模型请求访问权限
```

**或使用 CLI:**
```bash
# 检查模型访问状态
aws bedrock list-foundation-models \
  --region us-east-1 \
  --query 'modelSummaries[*].[modelId,modelName,customizationsSupported]' \
  --output table
```

---

## 🎯 **最佳实践**

### ✅ 推荐做法

1. **使用专用 IAM 用户**
   - 不要用部署 ECS 的凭证
   - 只授予 Bedrock 相关权限

2. **启用 CloudTrail 审计**
   ```bash
   # 跟踪 Bedrock API 调用
   aws cloudtrail lookup-events \
     --lookup-attributes AttributeKey=EventName,AttributeValue=InvokeModel
   ```

3. **设置成本告警**
   ```bash
   # 监控 Bedrock 成本
   aws cloudwatch put-metric-alarm \
     --alarm-name bedrock-cost-alert \
     --metric-name EstimatedCharges \
     --namespace AWS/Billing \
     --threshold 100
   ```

4. **使用成本优化的模型**
   - 开发/测试: Claude 3 Haiku（最便宜）
   - 生产: Claude 3.5 Sonnet（性价比高）

5. **配置多个区域的模型（高可用）**
   ```yaml
   model_list:
     - model_name: claude-us-east
       litellm_params:
         model: bedrock/anthropic.claude-3-sonnet-20240229-v1:0
         aws_region_name: us-east-1

     - model_name: claude-us-west
       litellm_params:
         model: bedrock/anthropic.claude-3-sonnet-20240229-v1:0
         aws_region_name: us-west-2
   ```

### ❌ 避免做法

1. ❌ 不要在 config.yaml 中硬编码凭证
2. ❌ 不要使用 Root 账户的凭证
3. ❌ 不要给过多权限（使用最小权限策略）
4. ❌ 不要忘记定期轮换访问密钥

---

## 📋 **配置检查清单**

部署前确认：

- [ ] 创建了 Bedrock 专用 IAM 用户
- [ ] 附加了正确的 Bedrock 权限
- [ ] 在 `terraform.tfvars` 中配置了 AK/SK
- [ ] 在 `config.yaml` 中添加了 Bedrock 模型
- [ ] 模型使用 `os.environ/AWS_ACCESS_KEY_ID` 引用
- [ ] 确认 Bedrock 在目标区域可用
- [ ] 申请了必要的模型访问权限
- [ ] 运行了 `terraform apply`
- [ ] 重新构建了 Docker 镜像 (`./build.sh`)
- [ ] 测试了 Bedrock 模型调用

---

## 🎓 **完整示例**

### 1. 创建 IAM 用户并获取凭证
```bash
aws iam create-user --user-name litellm-bedrock-user
aws iam create-access-key --user-name litellm-bedrock-user
aws iam attach-user-policy \
  --user-name litellm-bedrock-user \
  --policy-arn arn:aws:iam::aws:policy/AmazonBedrockFullAccess
```

### 2. 配置 terraform.tfvars
```hcl
aws_access_key_id     = "AKIAIOSFODNN7EXAMPLE"
aws_secret_access_key = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
```

### 3. 配置 config.yaml
```yaml
model_list:
  - model_name: claude-bedrock
    litellm_params:
      model: bedrock/anthropic.claude-3-5-sonnet-20240620-v1:0
      aws_access_key_id: os.environ/AWS_ACCESS_KEY_ID
      aws_secret_access_key: os.environ/AWS_SECRET_ACCESS_KEY
      aws_region_name: us-east-1
```

### 4. 部署
```bash
terraform apply
./build.sh
```

### 5. 测试
```bash
curl https://your-litellm.com/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer sk-your-key" \
  -d '{
    "model": "claude-bedrock",
    "messages": [{"role": "user", "content": "Hi"}]
  }'
```

---

**配置完成！现在你可以通过 LiteLLM 统一接口调用 Bedrock 模型了！** 🎉

需要帮助？查看日志：
```bash
aws logs tail /ecs/litellm --follow --filter-pattern "bedrock"
```
