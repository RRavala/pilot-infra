#!/usr/bin/env bash
# One-time setup, run by you in your own AWS account (CloudShell works fine).
# Creates: the Terraform state bucket, the GitHub OIDC provider, and the IAM role
# that the GitHub Actions workflow assumes. None of this is destroyed by the workflow.
#
# Usage: ./bootstrap.sh <owner>/<repo> [<owner>/<other-repo> ...]
#        e.g. ./bootstrap.sh RRavala/pilot-infra RRavala/flyway-postgres-demo
# Every repo listed may assume the role. Use the exact capitalization GitHub shows.
set -euo pipefail

[ $# -ge 1 ] || { echo "Usage: $0 <owner>/<repo> [<owner>/<repo> ...]" >&2; exit 1; }
REPOS=("$@")
REPO="${REPOS[0]}"
REGION="${AWS_REGION:-us-east-1}"
ROLE_NAME="pilot-infra-github-actions"

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
BUCKET="pilot-infra-tfstate-${ACCOUNT_ID}"
OIDC_URL="token.actions.githubusercontent.com"
OIDC_ARN="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_URL}"

echo "Account: ${ACCOUNT_ID}  Region: ${REGION}  Repos: ${REPOS[*]}"

# 1. State bucket --------------------------------------------------------------
if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  echo "State bucket exists: $BUCKET"
else
  echo "Creating state bucket: $BUCKET"
  if [ "$REGION" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "$BUCKET" --region "$REGION"
  else
    aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
      --create-bucket-configuration "LocationConstraint=${REGION}"
  fi
fi
aws s3api put-bucket-versioning --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled
aws s3api put-public-access-block --bucket "$BUCKET" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
aws s3api put-bucket-encryption --bucket "$BUCKET" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

# 2. GitHub OIDC provider --------------------------------------------------------
if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_ARN" >/dev/null 2>&1; then
  echo "OIDC provider exists"
else
  echo "Creating OIDC provider"
  aws iam create-open-id-connect-provider \
    --url "https://${OIDC_URL}" \
    --client-id-list sts.amazonaws.com \
    --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1 >/dev/null
fi

# 3. Deploy role ---------------------------------------------------------------
# GitHub may emit the OIDC subject as repo:Owner/Name:... or, with immutable IDs,
# repo:Owner@<id>/Name@<id>:... so allow both forms for each repo.
SUBS=""
for r in "${REPOS[@]}"; do
  owner="${r%%/*}"; name="${r#*/}"
  SUBS="${SUBS:+$SUBS, }\"repo:${owner}/${name}:*\", \"repo:${owner}@*/${name}@*:*\""
done

TRUST="$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Federated": "${OIDC_ARN}"},
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {"${OIDC_URL}:aud": "sts.amazonaws.com"},
      "StringLike":   {"${OIDC_URL}:sub": [${SUBS}]}
    }
  }]
}
EOF
)"

POLICY="$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {"Sid": "Rds", "Effect": "Allow", "Action": "rds:*", "Resource": "*"},
    {"Sid": "Ec2Network", "Effect": "Allow", "Action": [
      "ec2:Describe*", "ec2:CreateSecurityGroup", "ec2:DeleteSecurityGroup",
      "ec2:AuthorizeSecurityGroupIngress", "ec2:AuthorizeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupIngress", "ec2:RevokeSecurityGroupEgress",
      "ec2:ModifySecurityGroupRules", "ec2:UpdateSecurityGroupRuleDescriptionsIngress",
      "ec2:CreateTags", "ec2:DeleteTags"], "Resource": "*"},
    {"Sid": "ManagedMasterPassword", "Effect": "Allow", "Action": "secretsmanager:*", "Resource": "*"},
    {"Sid": "KmsForRdsAndSecrets", "Effect": "Allow", "Action": [
      "kms:DescribeKey", "kms:CreateGrant", "kms:Decrypt", "kms:GenerateDataKey*",
      "kms:ListAliases"], "Resource": "*"},
    {"Sid": "RdsServiceLinkedRole", "Effect": "Allow", "Action": "iam:CreateServiceLinkedRole",
     "Resource": "*", "Condition": {"StringEquals": {"iam:AWSServiceName": "rds.amazonaws.com"}}},
    {"Sid": "TerraformState", "Effect": "Allow", "Action": [
      "s3:ListBucket", "s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
     "Resource": ["arn:aws:s3:::${BUCKET}", "arn:aws:s3:::${BUCKET}/*"]}
  ]
}
EOF
)"

if aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
  echo "Updating role trust policy"
  aws iam update-assume-role-policy --role-name "$ROLE_NAME" --policy-document "$TRUST"
else
  echo "Creating role $ROLE_NAME"
  aws iam create-role --role-name "$ROLE_NAME" \
    --assume-role-policy-document "$TRUST" >/dev/null
fi
aws iam put-role-policy --role-name "$ROLE_NAME" \
  --policy-name pilot-infra --policy-document "$POLICY"

ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"

cat <<EOF

Done. In GitHub (each repo that will use the role, e.g. ${REPO}) > Settings > Secrets and variables > Actions > Variables, add:

  AWS_ROLE_ARN     = ${ROLE_ARN}
  TF_STATE_BUCKET  = ${BUCKET}
  ALLOWED_CIDR     = <your public IP>/32          (optional; can also be typed per run)
  NIGHTLY_DESTROY  = true                         (optional; enables the 1am auto-destroy)

Then create two environments under Settings > Environments: "deploy" and "destroy".
EOF
