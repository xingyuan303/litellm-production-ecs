# GitHub Actions 设置指南

本文档说明如何配置 GitHub Actions 以实现自动化构建和验证。

## 📋 已创建的 Workflow

### 1. **Terraform Check** (`terraform-check.yml`)
**触发时机:**
- Push 到 `main` 或 `develop` 分支
- 创建 Pull Request 到 `main` 分支
- 仅当 `.tf` 文件变更时触发

**自动执行:**
- ✅ Terraform 格式检查 (`terraform fmt`)
- ✅ Terraform 初始化验证
- ✅ Terraform 配置验证 (`terraform validate`)
- ✅ 安全扫描 (`tfsec`)
- ✅ 在 PR 中自动添加检查结果评论

### 2. **Docker Build and Push** (`docker-build.yml`)
**触发时机:**
- Push 到 `main` 分支
- 手动触发（通过 GitHub Actions 页面）
- 仅当 Docker 相关文件变更时触发

**自动执行:**
- ✅ 构建 Docker 镜像（linux/amd64）
- ✅ 运行 Trivy 安全扫描
- ✅ 推送镜像到 AWS ECR
- ✅ 自动打标签（latest, commit-sha）
- ✅ 生成构建摘要

### 3. **PR Comment** (`pr-comment.yml`)
**触发时机:**
- 创建或更新 Pull Request

**自动执行:**
- ✅ 自动在 PR 中添加有用的提示信息
- ✅ 说明自动化流程
- ✅ 提供部署命令

---

## ⚙️ 配置步骤

### 第一步：添加 GitHub Secrets

这些 Secrets 用于 Docker 构建工作流访问 AWS ECR。

1. 访问你的 GitHub 仓库
2. 点击 **Settings** → **Secrets and variables** → **Actions**
3. 点击 **New repository secret**
4. 添加以下 Secrets：

#### 必需的 Secrets:

| Secret Name | 说明 | 如何获取 |
|------------|------|---------|
| `AWS_ACCESS_KEY_ID` | AWS 访问密钥 ID | AWS IAM 控制台创建 |
| `AWS_SECRET_ACCESS_KEY` | AWS 访问密钥 | 与 Access Key ID 一起获取 |

#### 创建 AWS IAM 用户（用于 GitHub Actions）

```bash
# 1. 创建 IAM 用户
aws iam create-user --user-name github-actions-litellm

# 2. 创建访问密钥
aws iam create-access-key --user-name github-actions-litellm

# 输出会显示 AccessKeyId 和 SecretAccessKey
# 保存这些值，添加到 GitHub Secrets

# 3. 附加必要的权限策略
aws iam attach-user-policy \
  --user-name github-actions-litellm \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser
```

或者创建自定义策略（最小权限）:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload"
      ],
      "Resource": "*"
    }
  ]
}
```

---

## 🚀 使用方法

### Terraform 验证

**自动触发:**
每次修改 `.tf` 文件并 push 时自动运行。

**手动触发:**
无需手动触发，会自动运行。

**查看结果:**
1. 访问仓库的 **Actions** 标签
2. 点击 "Terraform Check" workflow
3. 查看检查结果

**修复格式问题:**
```bash
# 如果格式检查失败，运行:
terraform fmt -recursive

# 提交修改
git add .
git commit -m "Fix Terraform formatting"
git push
```

---

### Docker 构建和推送

**自动触发:**
- 推送到 `main` 分支时自动构建和推送镜像

**手动触发:**
1. 访问仓库的 **Actions** 标签
2. 点击 "Docker Build and Push" workflow
3. 点击右侧 "Run workflow" 按钮
4. 选择环境（production/staging/development）
5. 点击 "Run workflow"

**查看构建的镜像:**
```bash
# 列出 ECR 中的镜像
aws ecr describe-images \
  --repository-name litellm-dev \
  --region us-east-1
```

---

## 📊 工作流程图

### Pull Request 流程:
```
开发者创建 PR
    ↓
自动添加 PR 评论
    ↓
运行 Terraform 检查
    ↓
在 PR 中显示结果
    ↓
✅ 通过 → 可以合并
❌ 失败 → 需要修复
```

### Main 分支更新流程:
```
合并 PR 到 main
    ↓
触发 Docker 构建
    ↓
构建镜像
    ↓
运行安全扫描
    ↓
推送到 ECR
    ↓
生成构建摘要
```

---

## 🔍 查看 Workflow 运行状态

### 在 GitHub 网页上:
1. 访问仓库
2. 点击 **Actions** 标签
3. 查看所有 workflow 运行历史

### 使用 Badge（可选）:
在 `README.md` 中添加状态徽章：

```markdown
![Terraform Check](https://github.com/xingyuan303/litellm-production-ecs/actions/workflows/terraform-check.yml/badge.svg)
![Docker Build](https://github.com/xingyuan303/litellm-production-ecs/actions/workflows/docker-build.yml/badge.svg)
```

---

## 🛠️ 部署到 ECS

GitHub Actions **不会自动部署**到 ECS（安全考虑）。

构建完成后，你需要手动部署：

### 方式 1: 使用 build.sh 脚本
```bash
./build.sh
```

### 方式 2: 使用 AWS CLI
```bash
aws ecs update-service \
  --cluster litellm-ecs-cluster \
  --service litellm-service \
  --force-new-deployment \
  --region us-east-1
```

### 方式 3: 查看 Actions 页面的部署命令
每次构建完成后，在 Actions 的 Summary 页面会显示具体的部署命令。

---

## 🔐 安全最佳实践

### ✅ 已实施的安全措施:
1. **AWS 凭证** 存储在 GitHub Secrets 中（加密）
2. **Trivy 扫描** 自动检测 Docker 镜像漏洞
3. **tfsec 扫描** 自动检测 Terraform 配置安全问题
4. **最小权限** IAM 策略（仅 ECR 访问）
5. **CODEOWNERS** 文件确保关键变更需要审批

### ⚠️ 注意事项:
- ❌ 不要在代码中硬编码密钥
- ❌ 不要提交 `terraform.tfvars` 文件（已在 .gitignore）
- ✅ 定期轮换 AWS 访问密钥
- ✅ 审查所有 Pull Request 的变更

---

## 📈 监控和通知

### 失败通知:
当 workflow 失败时，GitHub 会自动发送邮件通知。

### 查看安全扫描结果:
1. 访问仓库的 **Security** 标签
2. 点击 **Code scanning alerts**
3. 查看 Trivy 和 tfsec 发现的问题

---

## 🐛 故障排查

### 问题 1: Terraform Check 失败

**症状**: "Terraform format check failed"

**解决方案**:
```bash
terraform fmt -recursive
git add .
git commit -m "Fix formatting"
git push
```

---

### 问题 2: Docker Build 失败 - AWS 认证错误

**症状**: "Unable to locate credentials"

**解决方案**:
1. 检查 GitHub Secrets 是否正确配置
2. 验证 IAM 用户是否有 ECR 权限
3. 确认 Secrets 名称完全匹配（区分大小写）

```bash
# 测试 IAM 用户权限
aws ecr describe-repositories \
  --region us-east-1 \
  --profile github-actions
```

---

### 问题 3: ECR Repository 不存在

**症状**: "RepositoryNotFoundException"

**解决方案**:
确保已经运行 `terraform apply` 创建了 ECR 仓库。

```bash
# 检查 ECR 仓库是否存在
aws ecr describe-repositories \
  --repository-names litellm-dev \
  --region us-east-1

# 如果不存在，运行
terraform apply
```

---

## 📚 更多资源

- [GitHub Actions 文档](https://docs.github.com/en/actions)
- [Terraform 最佳实践](https://www.terraform.io/docs/cloud/guides/recommended-practices/index.html)
- [AWS ECR 文档](https://docs.aws.amazon.com/ecr/)
- [Trivy 安全扫描](https://github.com/aquasecurity/trivy)

---

## 🎯 下一步

1. ✅ 配置 GitHub Secrets
2. ✅ 推送代码触发第一次构建
3. ✅ 查看 Actions 页面确认运行成功
4. ✅ 创建一个测试 PR 体验自动检查
5. ✅ 查看 Security 标签的扫描结果

---

**完成配置后，你的 CI/CD 就可以正常工作了！** 🎉

需要帮助？查看 [GitHub Issues](https://github.com/xingyuan303/litellm-production-ecs/issues)
