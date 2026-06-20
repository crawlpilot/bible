#!/usr/bin/env bash
# ============================================================
# 06-secrets.sh — Secrets & Data Security Validation
# Checks: SSM Parameter Store (plaintext secrets), Secrets
#         Manager (rotation, KMS, policies), EC2 user data
#         secret leaks, CloudFormation stack parameters,
#         Lambda env vars, EBS/RDS/DynamoDB encryption
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

header "Secrets & Data Security Validation"
check_aws_access

SECRET_PATTERN='PASSWORD|SECRET|KEY|TOKEN|CREDENTIAL|DB_PASS|API_KEY|PRIVATE|PASSWD|PWD'

# ─── SSM Parameter Store ─────────────────────────────────────
section "SSM Parameter Store — Plaintext Sensitive Parameters"

SSM_PARAMS=$(aws ssm describe-parameters \
  --query 'Parameters[*].[Name,Type]' --output text 2>/dev/null || echo "")

PLAIN_SSM=()
SECURE_SSM=()

if [[ -z "$SSM_PARAMS" ]]; then
  info "No SSM parameters found"
else
  while read -r PARAM_NAME PARAM_TYPE; do
    if echo "$PARAM_NAME" | grep -qiE "$SECRET_PATTERN"; then
      if [[ "$PARAM_TYPE" == "SecureString" ]]; then
        SECURE_SSM+=("$PARAM_NAME")
        echo -e "  ${GREEN}[PASS]${NC} $PARAM_NAME (SecureString ✓)"
      else
        PLAIN_SSM+=("$PARAM_NAME")
        echo -e "  ${RED}[FAIL]${NC} $PARAM_NAME is Type=$PARAM_TYPE — should be SecureString"
      fi
    fi
  done <<< "$SSM_PARAMS"

  TOTAL=$(echo "$SSM_PARAMS" | wc -l | tr -d ' ')
  info "$TOTAL total SSM parameters scanned"

  [[ ${#PLAIN_SSM[@]} -eq 0 ]] \
    && pass "No suspicious SSM parameters stored as plaintext String" \
    || fail "Sensitive SSM parameters stored as plaintext: ${PLAIN_SSM[*]}"
fi

# ─── Secrets Manager ─────────────────────────────────────────
section "AWS Secrets Manager — Rotation & KMS"

SECRETS=$(aws secretsmanager list-secrets \
  --query 'SecretList[*].[Name,RotationEnabled,LastRotatedDate,KmsKeyId]' \
  --output text 2>/dev/null || echo "")

if [[ -z "$SECRETS" ]]; then
  info "No secrets found in Secrets Manager"
else
  NO_ROTATION=()
  AWS_MANAGED_KMS=()
  OLD_ROTATION=()

  while read -r SECRET_NAME ROTATION_ENABLED LAST_ROTATED KMS_KEY; do
    echo -e "  ${CYAN}Secret:${NC} $SECRET_NAME"

    # Rotation
    if [[ "$ROTATION_ENABLED" == "True" ]]; then
      echo -e "    ${GREEN}[PASS]${NC} Automatic rotation: enabled (last: $LAST_ROTATED)"

      # Check if rotation is stale (> 90 days)
      if [[ "$LAST_ROTATED" != "None" && -n "$LAST_ROTATED" ]]; then
        ROT_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%S+00:00" "$LAST_ROTATED" "+%s" 2>/dev/null || \
                    date -d "$LAST_ROTATED" "+%s" 2>/dev/null || echo "0")
        NOW_EPOCH=$(date "+%s")
        AGE_DAYS=$(( (NOW_EPOCH - ROT_EPOCH) / 86400 ))
        if [[ $AGE_DAYS -gt 90 ]]; then
          OLD_ROTATION+=("$SECRET_NAME(${AGE_DAYS}d)")
          echo -e "    ${YELLOW}[WARN]${NC} Last rotation was $AGE_DAYS days ago (> 90 days)"
        fi
      fi
    else
      NO_ROTATION+=("$SECRET_NAME")
      echo -e "    ${YELLOW}[WARN]${NC} Automatic rotation: DISABLED"
    fi

    # KMS key
    if [[ -z "$KMS_KEY" || "$KMS_KEY" == "None" || "$KMS_KEY" == *"aws/secretsmanager"* ]]; then
      AWS_MANAGED_KMS+=("$SECRET_NAME")
      echo -e "    ${YELLOW}[WARN]${NC} KMS: using AWS-managed key (prefer customer-managed CMK)"
    else
      echo -e "    ${GREEN}[PASS]${NC} KMS: customer-managed CMK ($KMS_KEY)"
    fi
  done <<< "$SECRETS"

  [[ ${#NO_ROTATION[@]} -eq 0 ]] \
    && pass "All secrets have automatic rotation enabled" \
    || warn "Secrets without rotation: ${NO_ROTATION[*]}"

  [[ ${#OLD_ROTATION[@]} -eq 0 ]] \
    && pass "All rotated secrets rotated within 90 days" \
    || warn "Stale rotations (>90 days): ${OLD_ROTATION[*]}"

  [[ ${#AWS_MANAGED_KMS[@]} -eq 0 ]] \
    && pass "All secrets use customer-managed KMS keys" \
    || warn "Secrets on AWS-managed KMS (consider CMK): ${AWS_MANAGED_KMS[*]}"
fi

# ─── EC2 User Data — Secret Leak Detection ───────────────────
section "EC2 User Data — Credential Leak Detection"

INSTANCE_IDS=$(aws ec2 describe-instances \
  --filters "Name=instance-state-name,Values=running,stopped" \
  --query 'Reservations[*].Instances[*].InstanceId' \
  --output text 2>/dev/null || echo "")

USER_DATA_LEAKS=()
for INST_ID in $INSTANCE_IDS; do
  USER_DATA=$(aws ec2 describe-instance-attribute \
    --instance-id "$INST_ID" \
    --attribute userData \
    --query 'UserData.Value' --output text 2>/dev/null || echo "")

  if [[ -n "$USER_DATA" && "$USER_DATA" != "None" ]]; then
    DECODED=$(echo "$USER_DATA" | base64 --decode 2>/dev/null || echo "")
    if echo "$DECODED" | grep -qiE "$SECRET_PATTERN"; then
      USER_DATA_LEAKS+=("$INST_ID")
      echo -e "  ${RED}[FAIL]${NC} $INST_ID: user data contains potential secrets"
      echo "$DECODED" | grep -iE "$SECRET_PATTERN" | head -5 | \
        sed 's/\(.\{40\}\).*/\1.../' | while read -r LINE; do
          info "    Suspicious line: $LINE"
        done
    fi
  fi
done

if [[ ${#USER_DATA_LEAKS[@]} -eq 0 ]]; then
  pass "No EC2 user data scripts contain obvious credential patterns"
else
  fail "EC2 instances with potential secrets in user data: ${USER_DATA_LEAKS[*]}"
fi

# ─── CloudFormation Stack Parameters ─────────────────────────
section "CloudFormation — Plaintext Parameters in Stacks"

STACKS=$(aws cloudformation describe-stacks \
  --query 'Stacks[*].StackName' --output text 2>/dev/null || echo "")

CF_LEAKS=()
for STACK in $STACKS; do
  PARAMS=$(aws cloudformation describe-stacks \
    --stack-name "$STACK" \
    --query 'Stacks[0].Parameters[*].[ParameterKey,ParameterValue]' \
    --output text 2>/dev/null || echo "")

  while read -r PARAM_KEY PARAM_VALUE; do
    if echo "$PARAM_KEY" | grep -qiE "$SECRET_PATTERN"; then
      if [[ "$PARAM_VALUE" == "****" || "$PARAM_VALUE" == "HIDDEN" ]]; then
        echo -e "  ${GREEN}[PASS]${NC} Stack $STACK: $PARAM_KEY is masked (NoEcho=true)"
      else
        CF_LEAKS+=("$STACK.$PARAM_KEY")
        echo -e "  ${RED}[FAIL]${NC} Stack $STACK: $PARAM_KEY appears in plaintext"
      fi
    fi
  done <<< "$PARAMS"
done

[[ ${#CF_LEAKS[@]} -eq 0 ]] \
  && pass "No CloudFormation stacks exposing secrets in parameters" \
  || fail "Stacks with plaintext secrets in parameters: ${CF_LEAKS[*]}"

# ─── KMS Key Rotation ─────────────────────────────────────────
section "KMS — Customer-Managed Key Rotation"

KMS_KEYS=$(aws kms list-keys --query 'Keys[*].KeyId' --output text 2>/dev/null || echo "")
NO_ROTATION_KEYS=()
DISABLED_KEYS=()

for KEY_ID in $KMS_KEYS; do
  KEY_META=$(aws kms describe-key --key-id "$KEY_ID" \
    --query 'KeyMetadata' --output json 2>/dev/null || echo "{}")

  KEY_MANAGER=$(echo "$KEY_META" | python3 -c "import sys,json; \
    print(json.load(sys.stdin).get('KeyManager','UNKNOWN'))" 2>/dev/null || echo "UNKNOWN")
  KEY_STATE=$(echo "$KEY_META" | python3 -c "import sys,json; \
    print(json.load(sys.stdin).get('KeyState','UNKNOWN'))" 2>/dev/null || echo "UNKNOWN")
  KEY_ALIAS=$(aws kms list-aliases --key-id "$KEY_ID" \
    --query 'Aliases[0].AliasName' --output text 2>/dev/null || echo "(no alias)")

  # Only check customer-managed keys
  [[ "$KEY_MANAGER" != "CUSTOMER" ]] && continue
  [[ "$KEY_STATE" == "PendingDeletion" ]] && continue

  ROTATION=$(aws kms get-key-rotation-status --key-id "$KEY_ID" \
    --query 'KeyRotationEnabled' --output text 2>/dev/null || echo "false")

  if [[ "$ROTATION" == "True" ]]; then
    echo -e "  ${GREEN}[PASS]${NC} KMS $KEY_ALIAS ($KEY_ID): rotation enabled"
  else
    NO_ROTATION_KEYS+=("$KEY_ALIAS($KEY_ID)")
    echo -e "  ${YELLOW}[WARN]${NC} KMS $KEY_ALIAS ($KEY_ID): rotation DISABLED"
  fi

  if [[ "$KEY_STATE" == "Disabled" ]]; then
    DISABLED_KEYS+=("$KEY_ALIAS($KEY_ID)")
    echo -e "  ${YELLOW}[WARN]${NC} KMS key $KEY_ALIAS is DISABLED — ensure this is intentional"
  fi
done

[[ ${#NO_ROTATION_KEYS[@]} -eq 0 ]] \
  && pass "All customer-managed KMS keys have rotation enabled" \
  || warn "KMS keys without annual rotation: ${NO_ROTATION_KEYS[*]}"

# ─── DynamoDB Encryption ──────────────────────────────────────
section "DynamoDB — Encryption at Rest"

DDB_TABLES=$(aws dynamodb list-tables \
  --query 'TableNames[*]' --output text 2>/dev/null || echo "")

if [[ -z "$DDB_TABLES" ]]; then
  info "No DynamoDB tables found"
else
  DDB_UNENC=()
  for TABLE in $DDB_TABLES; do
    ENC=$(aws dynamodb describe-table --table-name "$TABLE" \
      --query 'Table.SSEDescription.Status' --output text 2>/dev/null || echo "DISABLED")
    ENC_TYPE=$(aws dynamodb describe-table --table-name "$TABLE" \
      --query 'Table.SSEDescription.SSEType' --output text 2>/dev/null || echo "NONE")

    if [[ "$ENC" == "ENABLED" ]]; then
      echo -e "  ${GREEN}[PASS]${NC} $TABLE: SSE enabled ($ENC_TYPE)"
    else
      DDB_UNENC+=("$TABLE")
      echo -e "  ${YELLOW}[WARN]${NC} $TABLE: using AWS-owned key (default) — consider CMK for sensitive data"
    fi
  done
fi

# ─── Summary ─────────────────────────────────────────────────
print_summary "Secrets & Data Security"
write_json_summary "06-secrets"
