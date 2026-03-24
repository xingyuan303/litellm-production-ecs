# ============================================
# AWS Secrets Manager Configuration
# ============================================

# OpenAI API Key
resource "aws_secretsmanager_secret" "openai_api_key" {
  count = var.openai_api_key != "" ? 1 : 0

  name        = "${var.project_name}/openai_api_key"
  description = "OpenAI API key for LiteLLM"

  tags = {
    Name        = "${var.project_name}-openai-key"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_secretsmanager_secret_version" "openai_api_key" {
  count = var.openai_api_key != "" ? 1 : 0

  secret_id     = aws_secretsmanager_secret.openai_api_key[0].id
  secret_string = var.openai_api_key
}

# Anthropic API Key
resource "aws_secretsmanager_secret" "anthropic_api_key" {
  count = var.anthropic_api_key != "" ? 1 : 0

  name        = "${var.project_name}/anthropic_api_key"
  description = "Anthropic (Claude) API key for LiteLLM"

  tags = {
    Name        = "${var.project_name}-anthropic-key"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_secretsmanager_secret_version" "anthropic_api_key" {
  count = var.anthropic_api_key != "" ? 1 : 0

  secret_id     = aws_secretsmanager_secret.anthropic_api_key[0].id
  secret_string = var.anthropic_api_key
}

# Azure API Key
resource "aws_secretsmanager_secret" "azure_api_key" {
  count = var.azure_api_key != "" ? 1 : 0

  name        = "${var.project_name}/azure_api_key"
  description = "Azure OpenAI API key for LiteLLM"

  tags = {
    Name        = "${var.project_name}-azure-key"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_secretsmanager_secret_version" "azure_api_key" {
  count = var.azure_api_key != "" ? 1 : 0

  secret_id     = aws_secretsmanager_secret.azure_api_key[0].id
  secret_string = var.azure_api_key
}

# Gemini API Key
resource "aws_secretsmanager_secret" "gemini_api_key" {
  count = var.gemini_api_key != "" ? 1 : 0

  name        = "${var.project_name}/gemini_api_key"
  description = "Google Gemini API key for LiteLLM"

  tags = {
    Name        = "${var.project_name}-gemini-key"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_secretsmanager_secret_version" "gemini_api_key" {
  count = var.gemini_api_key != "" ? 1 : 0

  secret_id     = aws_secretsmanager_secret.gemini_api_key[0].id
  secret_string = var.gemini_api_key
}

# AWS Access Key (for Bedrock)
resource "aws_secretsmanager_secret" "aws_access_key" {
  count = var.aws_access_key_id != "" ? 1 : 0

  name        = "${var.project_name}/aws_access_key_id"
  description = "AWS Access Key ID for Bedrock"

  tags = {
    Name        = "${var.project_name}-aws-access-key"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_secretsmanager_secret_version" "aws_access_key" {
  count = var.aws_access_key_id != "" ? 1 : 0

  secret_id     = aws_secretsmanager_secret.aws_access_key[0].id
  secret_string = var.aws_access_key_id
}

# AWS Secret Key (for Bedrock)
resource "aws_secretsmanager_secret" "aws_secret_key" {
  count = var.aws_secret_access_key != "" ? 1 : 0

  name        = "${var.project_name}/aws_secret_access_key"
  description = "AWS Secret Access Key for Bedrock"

  tags = {
    Name        = "${var.project_name}-aws-secret-key"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_secretsmanager_secret_version" "aws_secret_key" {
  count = var.aws_secret_access_key != "" ? 1 : 0

  secret_id     = aws_secretsmanager_secret.aws_secret_key[0].id
  secret_string = var.aws_secret_access_key
}
