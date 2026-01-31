#!/usr/bin/env bash
set -e

# Ghost Blog – Terraform backend setup
# Creates S3 bucket and DynamoDB table for Terraform state, then migrates state.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

REGION="${AWS_REGION:-ap-southeast-2}"
STATE_BUCKET_PREFIX="ghost-blog-terraform-state"
LOCK_TABLE_NAME="ghost-blog-terraform-locks"
STATE_KEY="ghost/terraform.tfstate"

echo "==> Getting AWS account ID..."
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
STATE_BUCKET="${STATE_BUCKET_PREFIX}-${ACCOUNT_ID}"

echo "==> Creating S3 bucket for Terraform state: ${STATE_BUCKET}"
if aws s3api head-bucket --bucket "$STATE_BUCKET" 2>/dev/null; then
  echo "    Bucket already exists."
else
  if [ "$REGION" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "$STATE_BUCKET" --region "$REGION"
  else
    aws s3api create-bucket \
      --bucket "$STATE_BUCKET" \
      --region "$REGION" \
      --create-bucket-configuration "LocationConstraint=${REGION}"
  fi
fi

echo "==> Enabling versioning on state bucket..."
aws s3api put-bucket-versioning \
  --bucket "$STATE_BUCKET" \
  --versioning-configuration Status=Enabled

echo "==> Enabling default encryption on state bucket..."
aws s3api put-bucket-encryption \
  --bucket "$STATE_BUCKET" \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      },
      "BucketKeyEnabled": true
    }]
  }'

echo "==> Creating DynamoDB table for state lock: ${LOCK_TABLE_NAME}"
if aws dynamodb describe-table --table-name "$LOCK_TABLE_NAME" --region "$REGION" 2>/dev/null; then
  echo "    Table already exists."
else
  aws dynamodb create-table \
    --table-name "$LOCK_TABLE_NAME" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "$REGION"
  echo "    Waiting for table to be active..."
  aws dynamodb wait table-exists --table-name "$LOCK_TABLE_NAME" --region "$REGION"
fi

echo "==> Writing backend config to backend.config..."
cat > backend.config << EOF
bucket         = "$STATE_BUCKET"
key            = "$STATE_KEY"
region         = "$REGION"
encrypt        = true
dynamodb_table = "$LOCK_TABLE_NAME"
EOF

echo "==> Configuring Terraform backend and migrating state..."
terraform init -migrate-state -input=false -backend-config=backend.config

echo ""
echo "==> Done. Terraform state is now in s3://${STATE_BUCKET}/${STATE_KEY}"
echo "    Backend config saved to backend.config (gitignored)."
echo "    Future runs: terraform init (uses .terraform cache); or terraform init -backend-config=backend.config if .terraform is missing."
