#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================"
echo "AWS CodeBuild Setup Script"
echo -e "========================================${NC}"

# Get variables from Terraform
echo -e "${YELLOW}Getting project information from Terraform...${NC}"
cd "$(dirname "$0")"
PROJECT_NAME=$(terraform output -raw project_name 2>/dev/null || echo "litellm")
ECR_URL=$(terraform output -raw ecr_repository_url)
ECS_CLUSTER=$(terraform output -raw ecs_cluster_name)
ECS_SERVICE=$(terraform output -raw ecs_service_name)
AWS_REGION=$(terraform output -raw aws_region)
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo -e "${GREEN}✓ Project: $PROJECT_NAME${NC}"
echo -e "${GREEN}✓ Region: $AWS_REGION${NC}"
echo -e "${GREEN}✓ ECR URL: $ECR_URL${NC}"

# Create CodeBuild service role
ROLE_NAME="${PROJECT_NAME}-codebuild-role"
echo -e "${YELLOW}Creating CodeBuild IAM role...${NC}"

# Check if role exists
if aws iam get-role --role-name "$ROLE_NAME" 2>/dev/null; then
    echo -e "${YELLOW}Role already exists, skipping...${NC}"
else
    cat > /tmp/codebuild-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "codebuild.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

    aws iam create-role \
        --role-name "$ROLE_NAME" \
        --assume-role-policy-document file:///tmp/codebuild-trust-policy.json

    # Attach necessary policies
    cat > /tmp/codebuild-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "*"
    },
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
    },
    {
      "Effect": "Allow",
      "Action": [
        "ecs:UpdateService",
        "ecs:DescribeServices"
      ],
      "Resource": "*"
    }
  ]
}
EOF

    aws iam put-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-name "${PROJECT_NAME}-codebuild-policy" \
        --policy-document file:///tmp/codebuild-policy.json

    echo -e "${GREEN}✓ IAM role created${NC}"
    sleep 10  # Wait for IAM role to propagate
fi

# Create CodeBuild project
PROJECT_BUILD_NAME="${PROJECT_NAME}-build"
echo -e "${YELLOW}Creating CodeBuild project...${NC}"

# Check if project exists
if aws codebuild batch-get-projects --names "$PROJECT_BUILD_NAME" --region "$AWS_REGION" --query 'projects[0].name' --output text 2>/dev/null | grep -q "$PROJECT_BUILD_NAME"; then
    echo -e "${YELLOW}CodeBuild project already exists, updating...${NC}"
    aws codebuild update-project \
        --name "$PROJECT_BUILD_NAME" \
        --region "$AWS_REGION" \
        --environment type=LINUX_CONTAINER,image=aws/codebuild/standard:7.0,computeType=BUILD_GENERAL1_SMALL,privilegedMode=true \
        --environment-variables \
            name=ECR_REPOSITORY_URL,value="$ECR_URL" \
            name=ECS_CLUSTER_NAME,value="$ECS_CLUSTER" \
            name=ECS_SERVICE_NAME,value="$ECS_SERVICE" \
            name=AWS_DEFAULT_REGION,value="$AWS_REGION" \
        --service-role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}"
else
    aws codebuild create-project \
        --name "$PROJECT_BUILD_NAME" \
        --source type=S3 \
        --artifacts type=NO_ARTIFACTS \
        --environment type=LINUX_CONTAINER,image=aws/codebuild/standard:7.0,computeType=BUILD_GENERAL1_SMALL,privilegedMode=true,environmentVariables="[{name=ECR_REPOSITORY_URL,value=$ECR_URL},{name=ECS_CLUSTER_NAME,value=$ECS_CLUSTER},{name=ECS_SERVICE_NAME,value=$ECS_SERVICE},{name=AWS_DEFAULT_REGION,value=$AWS_REGION}]" \
        --service-role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}" \
        --region "$AWS_REGION"

    echo -e "${GREEN}✓ CodeBuild project created${NC}"
fi

echo ""
echo -e "${GREEN}========================================"
echo "Setup Complete!"
echo -e "========================================${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Upload your code to CodeBuild:"
echo "   cd /Users/xyuanliu/litellm-production-ecs"
echo "   zip -r litellm-source.zip Dockerfile config.yaml buildspec.yml"
echo ""
echo "2. Start the build with the script:"
echo "   ./start-codebuild.sh"
echo ""
echo -e "${GREEN}Or manually trigger build in AWS Console:${NC}"
echo "https://console.aws.amazon.com/codesuite/codebuild/projects/${PROJECT_BUILD_NAME}/history?region=${AWS_REGION}"
