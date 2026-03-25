# 快速部署指南 - 从零开始

这是一份完整的新手指南，帮助您从零开始将 LiteLLM 部署到 AWS。

## 📋 前置要求

### 1. AWS 账户

**需要：**
- ✅ 一个 AWS 账户
- ✅ 管理员权限（或足够的权限创建 ECS、RDS、ALB 等资源）
- ✅ 信用卡（AWS 会收取资源使用费用）

**预估成本：** 最小配置约 $480/月

### 2. 安装工具

根据您的操作系统选择：

#### macOS

```bash
# 1. 安装 Homebrew（如果还没有）
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# 2. 安装 AWS CLI
brew install awscli

# 3. 安装 Terraform
brew install terraform

# 4. 安装 Docker
brew install --cask docker
# 然后启动 Docker Desktop 应用

# 5. 验证安装
aws --version      # 应显示: aws-cli/2.x.x
terraform --version # 应显示: Terraform v1.x.x
docker --version    # 应显示: Docker version 20.x.x
```

#### Windows

```powershell
# 使用 Chocolatey 包管理器
# 1. 以管理员身份打开 PowerShell，安装 Chocolatey
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

# 2. 安装工具
choco install awscli terraform docker-desktop -y

# 3. 重启 PowerShell 并验证
aws --version
terraform --version
docker --version
```

#### Linux (Ubuntu/Debian)

```bash
# 1. 安装 AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# 2. 安装 Terraform
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform

# 3. 安装 Docker
sudo apt-get update
sudo apt-get install docker.io docker-compose -y
sudo systemctl start docker
sudo usermod -aG docker $USER

# 4. 验证
aws --version
terraform --version
docker --version
```

---

## 🔐 第二步：配置 AWS 凭证

### 方式 1：创建 IAM 用户（推荐新手）

1. **登录 AWS 控制台**
   - 访问：https://console.aws.amazon.com/
   - 使用您的 AWS 账户登录

2. **创建 IAM 用户**
   ```
   a. 搜索栏输入 "IAM" → 点击进入 IAM 服务
   b. 左侧菜单：用户 (Users) → 创建用户 (Create user)
   c. 用户名：litellm-deploy
   d. 权限选项：直接附加策略 (Attach policies directly)
   e. 搜索并勾选以下策略：
      - AdministratorAccess (简单起见，生产环境应使用更细粒度权限)
   f. 点击"创建用户"
   ```

3. **创建访问密钥**
   ```
   a. 点击刚创建的用户 "litellm-deploy"
   b. 选择"安全凭证"标签页
   c. 点击"创建访问密钥" (Create access key)
   d. 用例选择：命令行界面 (CLI)
   e. 勾选"我了解..." → 下一步
   f. ⚠️ 重要：记录 Access Key ID 和 Secret Access Key
      （关闭后无法再次查看 Secret）
   ```

4. **配置 AWS CLI**

```bash
# 运行配置命令
aws configure

# 按提示输入（示例）：
# AWS Access Key ID [None]: AKIAIOSFODNN7EXAMPLE
# AWS Secret Access Key [None]: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
# Default region name [None]: us-east-1  (或 ap-northeast-1 for 东京)
# Default output format [None]: json
```

5. **验证配置**

```bash
# 测试连接
aws sts get-caller-identity

# 应该看到类似输出：
# {
#     "UserId": "AIDAI...",
#     "Account": "123456789012",
#     "Arn": "arn:aws:iam::123456789012:user/litellm-deploy"
# }
```

---

## ⚙️ 第三步：准备配置文件

### 1. 进入项目目录

```bash
cd /Users/xyuanliu/litellm-production-ecs
```

### 2. 复制配置文件模板

```bash
cp terraform.tfvars.example terraform.tfvars
```

### 3. 编辑配置文件

```bash
# 使用您喜欢的编辑器
vim terraform.tfvars
# 或
code terraform.tfvars
# 或
nano terraform.tfvars
```

### 4. 最小化配置（测试部署）

将以下内容粘贴到 `terraform.tfvars`：

```hcl
# ============================================
# 基础配置
# ============================================
project_name = "litellm"
environment  = "production"
aws_region   = "us-east-1"  # 或 "ap-northeast-1" (东京)

# ============================================
# 安全密钥（必须配置）
# ============================================

# 生成 Master Key（在终端运行）：
# echo "sk-$(openssl rand -hex 16)"
litellm_master_key = "sk-YOUR_GENERATED_KEY_HERE"

# 生成 Salt Key（在终端运行）：
# openssl rand -hex 32
litellm_salt_key = "YOUR_GENERATED_SALT_HERE"

# ============================================
# API Keys（至少配置一个）
# ============================================

# OpenAI（如果有）
openai_api_key = "sk-proj-your-openai-key-here"

# Anthropic（如果有）
anthropic_api_key = "sk-ant-your-anthropic-key-here"

# ============================================
# 数据库配置
# ============================================
db_instance_class = "db.t3.medium"
db_multi_az       = true

# ============================================
# HTTPS 配置（可选，首次部署建议禁用）
# ============================================
enable_https = false

# 如果要启用 HTTPS，需要：
# 1. 在 Route53 托管一个域名
# 2. 取消下面两行注释并填写
# domain_name       = "example.com"
# litellm_subdomain = "litellm.example.com"

# ============================================
# CloudFront（可选，首次部署建议禁用）
# ============================================
enable_cloudfront = false

# ============================================
# 安全设置（首次部署建议设为 false）
# ============================================
enable_deletion_protection = false
skip_final_snapshot        = true
```

### 5. 生成密钥

在终端运行以下命令生成安全密钥：

```bash
# 生成 Master Key
echo "sk-$(openssl rand -hex 16)"
# 输出示例: sk-a1b2c3d4e5f6789012345678

# 生成 Salt Key
openssl rand -hex 32
# 输出示例: a1b2c3d4e5f6789012345678901234567890123456789012345678901234

# 将生成的密钥复制到 terraform.tfvars 的对应位置
```

### 6. 配置 API Keys

如果您有 OpenAI 或 Anthropic 的 API Key，填写到 `terraform.tfvars` 的对应位置。

**获取 API Key：**
- OpenAI: https://platform.openai.com/api-keys
- Anthropic: https://console.anthropic.com/settings/keys

---

## 🚀 第四步：部署基础设施

### 1. 初始化 Terraform

```bash
# 在项目目录运行
terraform init

# 应该看到：
# Terraform has been successfully initialized!
```

**这一步做了什么？**
- 下载 AWS provider
- 准备工作目录
- 验证配置文件

### 2. 查看部署计划

```bash
terraform plan

# 这会显示将要创建的所有资源
# 仔细查看，确保没有错误
```

**预期输出：**
```
Plan: 50+ to add, 0 to change, 0 to destroy.
```

### 3. 执行部署

```bash
terraform apply

# 会再次显示计划并询问确认
# 输入 "yes" 确认部署
```

**⏱️ 部署时间：**
- 基础设施：15-20 分钟
- 包括：VPC、RDS、ECS、ALB 等

**部署过程中您会看到：**
```
aws_vpc.main: Creating...
aws_db_subnet_group.litellm: Creating...
aws_security_group.alb_sg: Creating...
...
Apply complete! Resources: 52 added, 0 changed, 0 destroyed.
```

### 4. 记录输出信息

部署完成后会显示重要信息：

```bash
# 重新显示输出信息
terraform output

# 应该看到：
# alb_url_http = "http://litellm-alb-1234567890.us-east-1.elb.amazonaws.com"
# ecr_repository_url = "123456789012.dkr.ecr.us-east-1.amazonaws.com/litellm-dev"
# ...
```

**保存这些信息！** 特别是：
- `alb_url_http` - 访问地址
- `ecr_repository_url` - Docker 镜像仓库
- `ecs_cluster_name` - ECS 集群名称
- `ecs_service_name` - ECS 服务名称

---

## 🐳 第五步：构建和部署 Docker 镜像

### 1. 登录到 ECR

```bash
# 获取 ECR 登录命令
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin \
  $(terraform output -raw ecr_repository_url | cut -d'/' -f1)

# 成功会显示：
# Login Succeeded
```

### 2. 构建 Docker 镜像

```bash
# 确保在项目目录
docker buildx build --platform linux/amd64 -t litellm:latest .

# ⏱️ 首次构建需要 5-10 分钟
# 会看到：
# [+] Building 300.5s (15/15) FINISHED
```

**如果遇到错误：**
```bash
# 确保 Docker 正在运行
docker ps

# 如果 Docker 未运行，启动 Docker Desktop
```

### 3. 标记镜像

```bash
# 获取 ECR URL
ECR_URL=$(terraform output -raw ecr_repository_url)

# 标记镜像
docker tag litellm:latest $ECR_URL:latest

# 验证
docker images | grep litellm
```

### 4. 推送镜像到 ECR

```bash
# 推送镜像
docker push $(terraform output -raw ecr_repository_url):latest

# ⏱️ 推送需要 3-5 分钟
# 会看到：
# latest: digest: sha256:abc123... size: 1234
```

### 5. 强制 ECS 更新

```bash
# 让 ECS 使用新镜像
aws ecs update-service \
  --cluster $(terraform output -raw ecs_cluster_name) \
  --service $(terraform output -raw ecs_service_name) \
  --force-new-deployment \
  --region us-east-1

# 成功会显示服务信息
```

---

## ✅ 第六步：验证部署

### 1. 等待服务稳定

```bash
# 查看 ECS 服务状态
aws ecs describe-services \
  --cluster $(terraform output -raw ecs_cluster_name) \
  --services $(terraform output -raw ecs_service_name) \
  --region us-east-1 \
  --query 'services[0].deployments[0].{Status:status,Running:runningCount,Desired:desiredCount}'

# 等待 runningCount == desiredCount
# 通常需要 3-5 分钟
```

### 2. 测试健康检查

```bash
# 获取访问 URL
ALB_URL=$(terraform output -raw alb_url_http)

# 测试健康端点
curl $ALB_URL/health

# 成功会显示：
# {"status":"ok"} 或类似响应
```

### 3. 测试 API

```bash
# 获取 Master Key
MASTER_KEY=$(terraform output -raw litellm_master_key)

# 测试列出模型
curl $ALB_URL/v1/models \
  -H "Authorization: Bearer $MASTER_KEY"

# 成功会显示可用的模型列表
```

### 4. 测试聊天 API

```bash
# 测试 GPT-4 调用（如果配置了 OpenAI）
curl $ALB_URL/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $MASTER_KEY" \
  -d '{
    "model": "gpt-4",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'

# 应该返回 AI 的响应
```

---

## 📊 第七步：监控和管理

### 查看日志

```bash
# 实时查看日志
aws logs tail /ecs/litellm --follow --region us-east-1

# 或查看最近 1 小时的日志
aws logs tail /ecs/litellm --since 1h --region us-east-1
```

### 查看运行的任务

```bash
# 列出运行的任务
aws ecs list-tasks \
  --cluster $(terraform output -raw ecs_cluster_name) \
  --region us-east-1

# 查看任务详情
aws ecs describe-tasks \
  --cluster $(terraform output -raw ecs_cluster_name) \
  --tasks <task-id> \
  --region us-east-1
```

### 手动扩容

```bash
# 将服务扩展到 5 个实例
aws ecs update-service \
  --cluster $(terraform output -raw ecs_cluster_name) \
  --service $(terraform output -raw ecs_service_name) \
  --desired-count 5 \
  --region us-east-1
```

---

## 🔧 故障排查

### 问题 1: "terraform apply" 失败

**错误：** `Error: error creating ... AccessDenied`

**解决：**
```bash
# 检查 AWS 凭证
aws sts get-caller-identity

# 如果失败，重新配置
aws configure
```

---

### 问题 2: ECS 任务无法启动

**解决：**
```bash
# 查看任务失败原因
aws ecs describe-tasks \
  --cluster $(terraform output -raw ecs_cluster_name) \
  --tasks $(aws ecs list-tasks --cluster $(terraform output -raw ecs_cluster_name) --query 'taskArns[0]' --output text) \
  --region us-east-1 \
  --query 'tasks[0].stoppedReason'

# 查看日志
aws logs tail /ecs/litellm --region us-east-1
```

常见原因：
- ❌ Docker 镜像未推送到 ECR
- ❌ 环境变量配置错误
- ❌ RDS 数据库未就绪

---

### 问题 3: 健康检查失败

**解决：**
```bash
# 检查 ALB 目标健康状态
aws elbv2 describe-target-health \
  --target-group-arn $(aws elbv2 describe-target-groups \
    --names litellm-tg \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text) \
  --region us-east-1

# 检查安全组规则
aws ec2 describe-security-groups \
  --filters Name=tag:Name,Values=litellm-alb-sg \
  --region us-east-1
```

---

### 问题 4: API 返回 401 Unauthorized

**原因：** Master Key 错误

**解决：**
```bash
# 验证 Master Key
terraform output -raw litellm_master_key

# 使用正确的 Key 测试
curl $ALB_URL/v1/models \
  -H "Authorization: Bearer $(terraform output -raw litellm_master_key)"
```

---

## 💰 成本管理

### 查看每月预估成本

**最小配置（测试环境）：**
- 2 个 ECS 任务: $288/月
- RDS db.t3.medium: $164/月
- ALB: $23/月
- 其他: $5/月
- **总计: ~$480/月**

### 节省成本的方法

1. **停止服务（不使用时）**
```bash
# 将服务缩减到 0
aws ecs update-service \
  --cluster $(terraform output -raw ecs_cluster_name) \
  --service $(terraform output -raw ecs_service_name) \
  --desired-count 0 \
  --region us-east-1

# 恢复时再设置回 2
```

2. **使用 Savings Plans**
- 访问：AWS Console → Billing → Savings Plans
- 1 年承诺可节省 30-40%

3. **删除不使用的日志**
```bash
# 设置日志保留期为 3 天（而非 7 天）
# 在 terraform.tfvars 中：
cloudwatch_log_retention_days = 3
```

---

## 🧹 清理资源（删除部署）

**⚠️ 警告：** 这会删除所有资源，包括数据库数据！

```bash
# 1. 备份重要数据（如果需要）

# 2. 删除所有资源
terraform destroy

# 3. 确认删除（输入 "yes"）

# ⏱️ 删除需要 10-15 分钟
```

**手动清理（如果需要）：**
```bash
# 清理 ECR 镜像
aws ecr batch-delete-image \
  --repository-name litellm-dev \
  --image-ids imageTag=latest \
  --region us-east-1

# 清理 CloudWatch 日志
aws logs delete-log-group \
  --log-group-name /ecs/litellm \
  --region us-east-1
```

---

## 📚 下一步

### 启用 HTTPS（推荐生产环境）

1. 在 Route53 托管域名
2. 修改 `terraform.tfvars`:
```hcl
enable_https = true
domain_name = "yourdomain.com"
litellm_subdomain = "litellm.yourdomain.com"
```
3. 重新部署：`terraform apply`

### 启用 CloudFront（优化全球访问）

查看：[CLOUDFRONT_SETUP.md](./CLOUDFRONT_SETUP.md)

### 配置多个 AI 模型

编辑 `config.yaml`，添加更多模型配置。

### 设置监控告警

1. 创建 SNS 主题
2. 在 `terraform.tfvars` 中设置 `alarm_sns_topic_arn`
3. 重新部署

---

## 🆘 需要帮助？

- 查看 [完整文档](./DEPLOYMENT.md)
- 查看 [常见问题](./README.md#故障排查)
- 提交 [GitHub Issue](https://github.com/xingyuan303/litellm-production-ecs/issues)

---

**恭喜！🎉 您已成功部署 LiteLLM 到 AWS！**
