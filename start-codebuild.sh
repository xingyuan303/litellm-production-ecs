#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================"
echo "Start CodeBuild Build"
echo -e "========================================${NC}"

cd "$(dirname "$0")"

# Get project info
PROJECT_NAME=$(terraform output -raw project_name 2>/dev/null || echo "litellm")
AWS_REGION=$(terraform output -raw aws_region)
PROJECT_BUILD_NAME="${PROJECT_NAME}-build"

echo -e "${YELLOW}Preparing source code...${NC}"

# Create source bundle
zip -q -r /tmp/litellm-source.zip \
    Dockerfile \
    config.yaml \
    buildspec.yml \
    -x "*.terraform*" "*.git*" "*.log"

echo -e "${GREEN}✓ Source code packaged${NC}"

# Upload to S3 (create bucket if needed)
BUCKET_NAME="${PROJECT_NAME}-codebuild-source-${AWS_REGION}"
echo -e "${YELLOW}Checking S3 bucket...${NC}"

if ! aws s3 ls "s3://${BUCKET_NAME}" 2>/dev/null; then
    echo -e "${YELLOW}Creating S3 bucket...${NC}"
    aws s3 mb "s3://${BUCKET_NAME}" --region "$AWS_REGION"
    aws s3api put-public-access-block \
        --bucket "${BUCKET_NAME}" \
        --public-access-block-configuration \
        "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
fi

echo -e "${YELLOW}Uploading source to S3...${NC}"
aws s3 cp /tmp/litellm-source.zip "s3://${BUCKET_NAME}/litellm-source.zip"
echo -e "${GREEN}✓ Source uploaded to S3${NC}"

# Start build
echo -e "${YELLOW}Starting CodeBuild...${NC}"
BUILD_ID=$(aws codebuild start-build \
    --project-name "$PROJECT_BUILD_NAME" \
    --region "$AWS_REGION" \
    --source-type-override S3 \
    --source-location-override "${BUCKET_NAME}/litellm-source.zip" \
    --query 'build.id' \
    --output text)

echo -e "${GREEN}✓ Build started: $BUILD_ID${NC}"
echo ""
echo -e "${YELLOW}Monitoring build progress...${NC}"
echo "Press Ctrl+C to stop monitoring (build will continue)"
echo ""

# Monitor build
while true; do
    BUILD_STATUS=$(aws codebuild batch-get-builds \
        --ids "$BUILD_ID" \
        --region "$AWS_REGION" \
        --query 'builds[0].buildStatus' \
        --output text)

    if [ "$BUILD_STATUS" == "IN_PROGRESS" ]; then
        echo -e "${YELLOW}Status: IN_PROGRESS...${NC}"
        sleep 10
    elif [ "$BUILD_STATUS" == "SUCCEEDED" ]; then
        echo -e "${GREEN}✓✓✓ Build SUCCEEDED ✓✓✓${NC}"
        echo ""
        echo -e "${GREEN}Docker image built and pushed to ECR${NC}"
        echo -e "${GREEN}ECS service updated automatically${NC}"
        echo ""
        echo "Check your service:"
        echo "  aws ecs describe-services --cluster $(terraform output -raw ecs_cluster_name) --services $(terraform output -raw ecs_service_name) --region $AWS_REGION"
        break
    elif [ "$BUILD_STATUS" == "FAILED" ]; then
        echo -e "${RED}✗ Build FAILED${NC}"
        echo ""
        echo "View logs:"
        echo "  aws codebuild batch-get-builds --ids $BUILD_ID --region $AWS_REGION"
        exit 1
    else
        echo -e "${YELLOW}Status: $BUILD_STATUS${NC}"
        sleep 5
    fi
done

# Clean up
rm -f /tmp/litellm-source.zip

echo ""
echo -e "${GREEN}========================================"
echo "Build Complete!"
echo -e "========================================${NC}"
echo ""
echo "Access your LiteLLM service:"
echo "  http://$(terraform output -raw alb_dns_name)"
echo ""
echo "View build details in AWS Console:"
echo "  https://console.aws.amazon.com/codesuite/codebuild/projects/${PROJECT_BUILD_NAME}/build/${BUILD_ID}/?region=${AWS_REGION}"
