# 日志管理指南

## 📊 日志配置说明

### 当前配置（生产环境优化）

```yaml
日志目标: CloudWatch Logs
日志组: /ecs/litellm
日志级别: INFO (默认)
保留期限: 7 天
详细调试: 禁用
```

---

## 🎛️ 日志级别说明

### INFO（推荐生产环境）✅
```
包含内容:
✅ API 请求和响应状态
✅ 错误和警告信息
✅ 性能指标
✅ 系统事件

不包含:
❌ 详细的请求体/响应体
❌ 内部状态变化
❌ LLM API 调用详情

日志量: ~10 GB/月
成本: ~$5/月
```

### DEBUG（开发/调试）
```
包含内容:
✅ INFO 级别的所有内容
✅ 详细的请求/响应内容
✅ 内部函数调用
✅ LLM API 交互详情

日志量: ~50-100 GB/月
成本: ~$25-50/月
```

### WARNING（成本优化）
```
包含内容:
✅ 警告信息
✅ 错误信息
✅ 严重问题

不包含:
❌ 正常的 API 请求日志
❌ 性能指标

日志量: ~2 GB/月
成本: ~$1-2/月
```

---

## 💰 成本详解

### CloudWatch Logs 定价（us-east-1）

| 项目 | 价格 | 说明 |
|-----|------|------|
| 数据摄取 | $0.50/GB | 写入日志的费用 |
| 数据存储 | $0.03/GB/月 | 存储的费用 |
| 数据查询 | 免费（前 5GB）| 查看日志 |

### 不同配置的月成本

| 日志级别 | 日志量/月 | 摄取成本 | 存储成本 | 总成本 |
|---------|----------|---------|---------|--------|
| WARNING | 2 GB | $1.00 | $0.06 | **$1.06** |
| INFO ✅ | 10 GB | $5.00 | $0.30 | **$5.30** |
| DEBUG | 50 GB | $25.00 | $1.50 | **$26.50** |
| DEBUG + detailed | 100 GB | $50.00 | $3.00 | **$53.00** |

---

## ⚙️ 如何修改日志级别

### 方法 1: 修改 Terraform 配置（推荐）

编辑 `terraform.tfvars`:

```hcl
# 选择日志级别
litellm_log_level = "INFO"    # INFO, DEBUG, WARNING, ERROR

# CloudWatch 保留天数
cloudwatch_log_retention_days = 7    # 1, 3, 5, 7, 14, 30, 60, 90, 120...
```

应用变更:
```bash
terraform apply
```

**注意**: 需要重新部署 ECS 任务才能生效。

---

### 方法 2: 临时启用调试模式（不推荐生产）

如果需要临时开启调试模式进行问题排查：

```bash
# 1. 更新环境变量
aws ecs update-service \
  --cluster litellm-ecs-cluster \
  --service litellm-service \
  --force-new-deployment

# 2. 修改任务定义，添加环境变量
LOG_LEVEL=DEBUG

# 3. 排查完成后记得改回 INFO
```

---

## 🔍 查看和分析日志

### 实时查看日志

```bash
# 实时流式查看
aws logs tail /ecs/litellm --follow

# 查看最近 1 小时
aws logs tail /ecs/litellm --since 1h

# 过滤特定内容
aws logs tail /ecs/litellm --filter-pattern "ERROR"
```

### 查询历史日志

```bash
# 查询过去 24 小时的错误
aws logs filter-log-events \
  --log-group-name /ecs/litellm \
  --start-time $(date -d '24 hours ago' +%s)000 \
  --filter-pattern "ERROR"

# 导出日志到文件
aws logs filter-log-events \
  --log-group-name /ecs/litellm \
  --start-time $(date -d '7 days ago' +%s)000 > logs-export.json
```

### CloudWatch Insights 查询

在 AWS 控制台的 CloudWatch → Insights 中运行：

```sql
# 查询最近 1 小时的错误
fields @timestamp, @message
| filter @message like /ERROR/
| sort @timestamp desc
| limit 100

# 统计请求数量
fields @timestamp
| filter @message like /POST/
| stats count() by bin(5m)

# 查询响应时间
fields @timestamp, @message
| filter @message like /response_time/
| parse @message "response_time: * ms" as latency
| stats avg(latency), max(latency), p99(latency)
```

---

## 📉 日志成本优化建议

### 1. 调整保留期限

```hcl
# 生产环境
cloudwatch_log_retention_days = 7    # 推荐

# 开发环境
cloudwatch_log_retention_days = 3    # 节省 40% 存储成本

# 合规要求
cloudwatch_log_retention_days = 90   # 满足审计需求
```

### 2. 使用日志过滤

在 `config.yaml` 中配置 LiteLLM 日志过滤：

```yaml
litellm_settings:
  set_verbose: false           # 禁用详细日志
  success_callback: []         # 不记录成功回调
  failure_callback: ["slack"]  # 只在失败时通知
```

### 3. 按环境配置

```hcl
# 生产环境（terraform.tfvars）
litellm_log_level = "INFO"
cloudwatch_log_retention_days = 7

# 开发环境（terraform-dev.tfvars）
litellm_log_level = "DEBUG"
cloudwatch_log_retention_days = 1
```

### 4. 导出到 S3（长期存储）

成本更低的长期日志存储方案：

```bash
# 每周导出日志到 S3
aws logs create-export-task \
  --log-group-name /ecs/litellm \
  --from $(date -d '7 days ago' +%s)000 \
  --to $(date +%s)000 \
  --destination s3-bucket-name \
  --destination-prefix litellm-logs/

# S3 存储成本: $0.023/GB/月（比 CloudWatch 便宜 24%）
```

---

## 🚨 日志监控告警

### 设置日志错误告警

```hcl
# 在 autoscaling.tf 中已配置
resource "aws_cloudwatch_metric_alarm" "log_errors" {
  alarm_name          = "litellm-high-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ERROR"
  namespace           = "LiteLLM"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "Error rate is too high"
}
```

### 创建日志指标过滤器

```bash
# 统计 ERROR 数量
aws logs put-metric-filter \
  --log-group-name /ecs/litellm \
  --filter-name ErrorCount \
  --filter-pattern "[ERROR]" \
  --metric-transformations \
    metricName=ErrorCount,metricNamespace=LiteLLM,metricValue=1
```

---

## 📋 日志最佳实践

### ✅ 推荐做法

1. **生产环境使用 INFO 级别**
   - 足够的信息用于故障排查
   - 成本可控

2. **设置合理的保留期限**
   - 生产: 7-14 天
   - 开发: 1-3 天

3. **启用日志指标和告警**
   - 监控错误率
   - 监控响应时间

4. **定期审查日志量**
   ```bash
   aws cloudwatch get-metric-statistics \
     --namespace AWS/Logs \
     --metric-name IncomingBytes \
     --dimensions Name=LogGroupName,Value=/ecs/litellm \
     --start-time $(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%S) \
     --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
     --period 86400 \
     --statistics Sum
   ```

5. **使用日志采样（高流量场景）**
   ```yaml
   # config.yaml
   litellm_settings:
     success_callback: []  # 不记录所有成功请求
     set_verbose: false    # 关闭详细模式
   ```

### ❌ 避免做法

1. **生产环境启用 DEBUG**
   - 日志量爆炸
   - 成本激增
   - 可能影响性能

2. **无限期保留日志**
   - 存储成本持续增长
   - 查询性能下降

3. **记录敏感信息**
   - API 密钥
   - 用户个人信息
   - 完整的请求/响应体

---

## 🔐 日志安全

### 确保日志中不包含敏感信息

LiteLLM 默认会脱敏以下信息：
- ✅ API 密钥（显示为 sk-***）
- ✅ 数据库密码
- ⚠️ 用户输入内容（在 DEBUG 模式下会记录）

**建议**: 在生产环境禁用详细日志，避免记录完整的用户输入。

---

## 📊 监控日志成本

### 创建成本告警

```bash
# 设置 CloudWatch Logs 成本告警
aws cloudwatch put-metric-alarm \
  --alarm-name litellm-logs-cost \
  --alarm-description "Alert when logs cost exceeds budget" \
  --metric-name EstimatedCharges \
  --namespace AWS/Billing \
  --statistic Maximum \
  --period 86400 \
  --evaluation-periods 1 \
  --threshold 10 \
  --comparison-operator GreaterThanThreshold
```

### 查看当月成本

```bash
# 使用 AWS Cost Explorer API
aws ce get-cost-and-usage \
  --time-period Start=$(date -u -d 'month ago' +%Y-%m-01),End=$(date -u +%Y-%m-%d) \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --filter file://filter.json

# filter.json
{
  "Dimensions": {
    "Key": "SERVICE",
    "Values": ["Amazon CloudWatch Logs"]
  }
}
```

---

## 🎯 快速配置指南

### 场景 1: 生产环境（默认）✅

```hcl
# terraform.tfvars
litellm_log_level = "INFO"
cloudwatch_log_retention_days = 7

预期成本: ~$5/月
日志量: ~10 GB/月
```

### 场景 2: 开发环境

```hcl
# terraform.tfvars
litellm_log_level = "DEBUG"
cloudwatch_log_retention_days = 3

预期成本: ~$15/月
日志量: ~30 GB/月
```

### 场景 3: 成本敏感

```hcl
# terraform.tfvars
litellm_log_level = "WARNING"
cloudwatch_log_retention_days = 3

预期成本: ~$1/月
日志量: ~2 GB/月
```

### 场景 4: 合规要求

```hcl
# terraform.tfvars
litellm_log_level = "INFO"
cloudwatch_log_retention_days = 90

预期成本: ~$15/月
日志量: ~10 GB/月（存储成本增加）
```

---

## 📞 获取帮助

- **查看实时日志**: `aws logs tail /ecs/litellm --follow`
- **查询历史日志**: 使用 CloudWatch Insights
- **成本监控**: CloudWatch Billing Dashboard

---

**日志是排查问题的关键，但也要控制成本！** 📊
