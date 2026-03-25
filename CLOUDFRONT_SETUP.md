# CloudFront 配置指南

CloudFront 可以加速全球访问，特别适合从亚洲、欧洲等远离 ALB 部署区域的用户访问。

## 🌍 两种配置方式

### 方式 1: CloudFront 默认域名 ⚡️ **最简单**

**优点：**
- ✅ 无需 Route53
- ✅ 无需额外 ACM 证书
- ✅ 5 分钟即可部署
- ✅ 免费 HTTPS

**缺点：**
- ❌ 域名不好看（如 `d111111abcdef8.cloudfront.net`）
- ❌ 无法自定义

**配置步骤：**

```hcl
# terraform.tfvars

# 1. 启用 CloudFront
enable_cloudfront = true

# 2. 选择价格等级（可选）
cloudfront_price_class = "PriceClass_All"  # 全球所有边缘节点

# 3. 就这样！无需其他配置
```

**部署：**

```bash
terraform apply
```

**访问：**

```bash
# 部署完成后，获取 CloudFront 域名
terraform output cloudfront_url

# 输出示例：
# https://d111111abcdef8.cloudfront.net

# 测试
curl https://d111111abcdef8.cloudfront.net/health
```

---

### 方式 2: CloudFront + 自定义域名 🎨 **推荐生产环境**

**优点：**
- ✅ 专业的自定义域名（如 `api.yourdomain.com`）
- ✅ 品牌形象好
- ✅ 易于记忆

**要求：**
- ⚠️ 需要 Route53 托管域名
- ⚠️ 需要额外的 ACM 证书（自动创建，免费）
- ⚠️ 部署时间约 20-30 分钟

**配置步骤：**

```hcl
# terraform.tfvars

# 1. 启用 HTTPS 和 Route53
enable_https = true
domain_name  = "example.com"  # 你的根域名

# 2. 启用 CloudFront
enable_cloudfront = true

# 3. 设置 CloudFront 自定义域名
cloudfront_custom_domain = "api.example.com"  # 或 litellm.example.com

# 4. 选择价格等级
cloudfront_price_class = "PriceClass_All"

# 5. 可选：启用 WAF 防护
enable_waf = true
waf_rate_limit = 2000
```

**部署：**

```bash
terraform apply
```

**访问：**

```bash
# 部署完成后
terraform output cloudfront_custom_domain_url

# 输出：https://api.example.com

# 测试
curl https://api.example.com/health
```

---

## 📊 完整配置对比

| 配置项 | 方式 1: 默认域名 | 方式 2: 自定义域名 |
|--------|-----------------|-------------------|
| **enable_cloudfront** | `true` | `true` |
| **enable_https** | 不需要 | `true` |
| **domain_name** | 不需要 | `"example.com"` |
| **cloudfront_custom_domain** | `""` (空) | `"api.example.com"` |
| **Route53 要求** | ❌ 不需要 | ✅ 需要 |
| **额外证书** | ❌ 不需要 | ✅ 自动创建（us-east-1） |
| **部署时间** | ~5 分钟 | ~20-30 分钟 |
| **访问 URL** | `https://d123.cloudfront.net` | `https://api.example.com` |

---

## 💰 成本对比

### 方式 1: 默认域名

| 项目 | 费用 |
|-----|------|
| CloudFront 数据传输（10TB/月） | ~$850/月 |
| CloudFront 请求（100M 请求） | ~$10/月 |
| Route53 | **$0**（不需要） |
| ACM 证书 | **$0**（免费） |
| **总计** | **~$860/月** |

### 方式 2: 自定义域名

| 项目 | 费用 |
|-----|------|
| CloudFront 数据传输（10TB/月） | ~$850/月 |
| CloudFront 请求（100M 请求） | ~$10/月 |
| Route53 托管区域 | $0.50/月 |
| Route53 查询（100M 查询） | $40/月 |
| ACM 证书 | **$0**（免费） |
| **总计** | **~$900/月** |

**差异：** 每月约 $40（Route53 查询费用）

---

## 🚀 价格等级选择

CloudFront 提供 3 个价格等级：

### PriceClass_All（全球）

```hcl
cloudfront_price_class = "PriceClass_All"
```

- ✅ 所有边缘节点（全球 400+ 个）
- ✅ 最佳性能
- 💰 最高成本
- 🌍 覆盖：全球所有区域

**推荐用于：** 全球用户访问

---

### PriceClass_200（主要区域）⭐️ **推荐**

```hcl
cloudfront_price_class = "PriceClass_200"
```

- ✅ 美洲、欧洲、亚洲、中东、非洲
- ✅ 性能良好
- 💰 中等成本
- 🌍 覆盖：99% 的用户

**推荐用于：** 大部分场景

---

### PriceClass_100（基础）

```hcl
cloudfront_price_class = "PriceClass_100"
```

- ✅ 美洲和欧洲
- ❌ 亚洲用户体验较差
- 💰 最低成本
- 🌍 覆盖：北美和欧洲

**推荐用于：** 仅北美/欧洲用户

---

## 🛡️ AWS WAF 配置（可选）

WAF 提供额外的安全防护：

```hcl
# terraform.tfvars

enable_waf = true
waf_rate_limit = 2000  # 每个 IP 每 5 分钟最多 2000 请求

# 可选：地理限制
cloudfront_geo_restriction_type = "whitelist"
cloudfront_geo_restriction_locations = ["US", "CN", "JP", "SG", "KR"]
```

**WAF 规则：**
1. ✅ 速率限制（防止 DDoS）
2. ✅ AWS 托管规则 - 通用防护
3. ✅ AWS 托管规则 - 已知恶意输入

**成本：**
- WAF Web ACL: $5/月
- WAF 规则: $1/月/规则（3 个规则 = $3/月）
- WAF 请求: $0.60/百万请求

**总计：** 约 $8/月 + 请求费用

---

## 📋 部署清单

### 方式 1 清单

- [ ] 设置 `enable_cloudfront = true`
- [ ] 选择 `cloudfront_price_class`
- [ ] 运行 `terraform apply`
- [ ] 等待 5-10 分钟
- [ ] 使用 `terraform output cloudfront_url` 获取访问地址
- [ ] 测试访问

### 方式 2 清单

- [ ] 确保域名已在 Route53 托管
- [ ] 设置 `enable_https = true`
- [ ] 设置 `domain_name = "example.com"`
- [ ] 设置 `enable_cloudfront = true`
- [ ] 设置 `cloudfront_custom_domain = "api.example.com"`
- [ ] 选择 `cloudfront_price_class`
- [ ] 运行 `terraform apply`
- [ ] 等待 20-30 分钟（包括 ACM 证书验证和 CloudFront 部署）
- [ ] 使用 `terraform output cloudfront_custom_domain_url` 获取访问地址
- [ ] 测试访问

---

## 🧪 测试 CloudFront

### 验证 CloudFront 是否工作

```bash
# 方式 1: 检查响应头
curl -I https://your-cloudfront-domain.com/health

# 应该看到:
# x-cache: Hit from cloudfront
# x-amz-cf-pop: NRT57-C1 (东京边缘节点)

# 方式 2: 测试延迟
time curl https://your-cloudfront-domain.com/health

# 对比直接访问 ALB
time curl http://your-alb-dns.amazonaws.com/health
```

### 测试 API 调用

```bash
# 获取 CloudFront URL
CLOUDFRONT_URL=$(terraform output -raw cloudfront_url)

# 或自定义域名
CLOUDFRONT_URL=$(terraform output -raw cloudfront_custom_domain_url)

# 测试健康检查
curl $CLOUDFRONT_URL/health

# 测试 API
curl $CLOUDFRONT_URL/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer sk-your-key" \
  -d '{
    "model": "gpt-4",
    "messages": [{"role": "user", "content": "Hello"}]
  }'
```

---

## 🔧 故障排查

### 问题 1: CloudFront 返回 502 Bad Gateway

**原因：** ALB 健康检查失败或 ECS 任务未启动

**解决：**

```bash
# 检查 ALB 目标健康状态
aws elbv2 describe-target-health \
  --target-group-arn $(terraform output -raw alb_target_group_arn)

# 检查 ECS 服务状态
aws ecs describe-services \
  --cluster $(terraform output -raw ecs_cluster_name) \
  --services $(terraform output -raw ecs_service_name)
```

---

### 问题 2: 自定义域名无法访问

**原因：** DNS 未生效或证书未验证

**解决：**

```bash
# 检查 DNS 解析
dig api.example.com

# 应该返回 CloudFront 域名的 CNAME

# 检查证书状态
aws acm list-certificates --region us-east-1

# 等待 DNS 传播（最多 48 小时，通常 5-10 分钟）
```

---

### 问题 3: 部署很慢（超过 30 分钟）

**原因：** CloudFront 全球分发需要时间

**解决：**

```bash
# 检查 CloudFront 部署状态
aws cloudfront get-distribution \
  --id $(terraform output -raw cloudfront_distribution_id) \
  --query 'Distribution.Status'

# Status 应该从 "InProgress" 变为 "Deployed"

# 可以先使用 ALB 直接访问
terraform output alb_url_http
```

---

## 📈 监控 CloudFront

### CloudWatch 指标

```bash
# 查看 CloudFront 请求数
aws cloudwatch get-metric-statistics \
  --namespace AWS/CloudFront \
  --metric-name Requests \
  --dimensions Name=DistributionId,Value=$(terraform output -raw cloudfront_distribution_id) \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum

# 查看错误率
aws cloudwatch get-metric-statistics \
  --namespace AWS/CloudFront \
  --metric-name 4xxErrorRate \
  --dimensions Name=DistributionId,Value=$(terraform output -raw cloudfront_distribution_id) \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average
```

---

## 💡 最佳实践

1. **生产环境推荐：**
   - ✅ 使用方式 2（自定义域名）
   - ✅ 启用 WAF
   - ✅ 使用 `PriceClass_200`
   - ✅ 启用 CloudFront 日志

2. **测试环境：**
   - ✅ 使用方式 1（默认域名）
   - ❌ 不启用 WAF
   - ✅ 使用 `PriceClass_100`

3. **成本优化：**
   - 使用 `PriceClass_200` 而非 `PriceClass_All`（节省 10-20%）
   - 只在需要时启用 WAF
   - 定期清理 CloudFront 日志

4. **性能优化：**
   - 保持 API 缓存 TTL 为 0（动态内容）
   - 使用 HTTP/2 和压缩
   - 监控缓存命中率

---

## 📚 相关文档

- [AWS CloudFront 文档](https://docs.aws.amazon.com/cloudfront/)
- [AWS WAF 文档](https://docs.aws.amazon.com/waf/)
- [CloudFront 价格](https://aws.amazon.com/cloudfront/pricing/)
- [主 README](./README.md)
- [部署指南](./DEPLOYMENT.md)

---

**问题？** 查看 [故障排查](#故障排查) 或提交 Issue。
