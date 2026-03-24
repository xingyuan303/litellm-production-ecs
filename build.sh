#!/bin/bash

# ============================================
# LiteLLM Docker Build and Deploy Script
# ============================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
AWS_REGION=${1:-us-east-1}
AWS_PROFILE=${2:-default}

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}LiteLLM Build and Deploy Script${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Check if Terraform outputs are available
if ! command -v terraform &> /dev/null; then
    echo -e "${RED}Error: terraform command not found${NC}"
    exit 1
fi

# Get ECR repository URL from Terraform
echo -e "${YELLOW}Getting ECR repository URL from Terraform...${NC}"
ECR_URL=$(terraform output -raw ecr_repository_url 2>/dev/null)
if [ -z "$ECR_URL" ]; then
    echo -e "${RED}Error: Could not get ECR URL from Terraform${NC}"
    echo -e "${YELLOW}Have you run 'terraform apply' yet?${NC}"
    exit 1
fi
echo -e "${GREEN}ECR URL: $ECR_URL${NC}"

# Get ECS cluster and service names
CLUSTER_NAME=$(terraform output -raw ecs_cluster_name 2>/dev/null)
SERVICE_NAME=$(terraform output -raw ecs_service_name 2>/dev/null)

# Get AWS Account ID
echo -e "${YELLOW}Getting AWS account ID...${NC}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --profile $AWS_PROFILE)
echo -e "${GREEN}Account ID: $ACCOUNT_ID${NC}"

# Login to ECR
echo -e "${YELLOW}Logging into ECR...${NC}"
aws ecr get-login-password --region $AWS_REGION --profile $AWS_PROFILE | \
    docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ ECR login successful${NC}"
else
    echo -e "${RED}✗ ECR login failed${NC}"
    exit 1
fi

# Build Docker image
echo -e "${YELLOW}Building Docker image...${NC}"
docker buildx build --platform linux/amd64 -t litellm-dev:latest .

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Docker build successful${NC}"
else
    echo -e "${RED}✗ Docker build failed${NC}"
    exit 1
fi

# Tag image
echo -e "${YELLOW}Tagging image...${NC}"
docker tag litellm-dev:latest $ECR_URL:latest

# Push to ECR
echo -e "${YELLOW}Pushing image to ECR...${NC}"
docker push $ECR_URL:latest

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Image pushed successfully${NC}"
else
    echo -e "${RED}✗ Image push failed${NC}"
    exit 1
fi

# Force ECS service update
echo -e "${YELLOW}Forcing ECS service update...${NC}"
aws ecs update-service \
    --cluster $CLUSTER_NAME \
    --service $SERVICE_NAME \
    --force-new-deployment \
    --region $AWS_REGION \
    --profile $AWS_PROFILE > /dev/null

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ ECS service update initiated${NC}"
else
    echo -e "${RED}✗ ECS service update failed${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Deployment Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "Image: ${GREEN}$ECR_URL:latest${NC}"
echo -e "Cluster: ${GREEN}$CLUSTER_NAME${NC}"
echo -e "Service: ${GREEN}$SERVICE_NAME${NC}"
echo ""
echo -e "${YELLOW}Monitor deployment progress:${NC}"
echo -e "aws ecs describe-services --cluster $CLUSTER_NAME --services $SERVICE_NAME --region $AWS_REGION"
echo ""
echo -e "${YELLOW}View logs:${NC}"
echo -e "aws logs tail /ecs/litellm --follow --region $AWS_REGION"
echo ""
