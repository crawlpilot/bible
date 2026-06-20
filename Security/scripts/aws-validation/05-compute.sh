#!/usr/bin/env bash
# ============================================================
# 05-compute.sh — Compute Security Validation
# Checks: EC2 (IMDSv2, EBS encryption, public IPs, key pairs)
#         Lambda (env secrets, resource policy, in-VPC, role)
#         ECS (privileged containers, task roles, secrets)
#         EKS (endpoint access, encryption, audit logs)
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

header "Compute Security Validation"
check_aws_access

# ════════════════════════════════════════════════════════════
# EC2
# ════════════════════════════════════════════════════════════
section "EC2 — IMDSv2 Enforcement"

INSTANCES=$(aws ec2 describe-instances \
  --filters "Name=instance-state-name,Values=running" \
  --query 'Reservations[*].Instances[*].[InstanceId,MetadataOptions.HttpTokens,MetadataOptions.HttpPutResponseHopLimit,PublicIpAddress,Tags[?Key==`Name`].Value|[0]]' \
  --output text 2>/dev/null || echo "")

IMDSV1_INSTANCES=()
HIGH_HOP_INSTANCES=()

if [[ -z "$INSTANCES" ]]; then
  info "No running EC2 instances found"
else
  while read -r INST_ID HTTP_TOKENS HOP_LIMIT PUB_IP NAME; do
    if [[ "$HTTP_TOKENS" != "required" ]]; then
      IMDSV1_INSTANCES+=("$INST_ID")
      echo -e "  ${RED}[FAIL]${NC} $INST_ID (${NAME:-no-name}): IMDSv2 NOT required (HttpTokens=$HTTP_TOKENS)"
    else
      echo -e "  ${GREEN}[PASS]${NC} $INST_ID (${NAME:-no-name}): IMDSv2 required"
    fi
    if [[ "$HOP_LIMIT" -gt 1 ]]; then
      HIGH_HOP_INSTANCES+=("$INST_ID(hopLimit=$HOP_LIMIT)")
      echo -e "  ${YELLOW}[WARN]${NC} $INST_ID: hop limit $HOP_LIMIT > 1 — containers can reach IMDS"
    fi
  done <<< "$INSTANCES"
fi

[[ ${#IMDSV1_INSTANCES[@]} -eq 0 ]] \
  && pass "All running instances enforce IMDSv2" \
  || fail "Instances still allowing IMDSv1: ${IMDSV1_INSTANCES[*]}"

[[ ${#HIGH_HOP_INSTANCES[@]} -eq 0 ]] \
  && pass "All instances have hop limit = 1 (containers cannot reach IMDS)" \
  || warn "High hop limit instances: ${HIGH_HOP_INSTANCES[*]}"

section "EC2 — EBS Default Encryption"

EBS_ENC=$(aws ec2 get-ebs-encryption-by-default \
  --query 'EbsEncryptionByDefault' --output text 2>/dev/null || echo "False")
if [[ "$EBS_ENC" == "True" ]]; then
  EBS_KEY=$(aws ec2 get-ebs-default-kms-key-id \
    --query 'KmsKeyId' --output text 2>/dev/null || echo "aws/ebs")
  pass "EBS default encryption enabled (KMS: $EBS_KEY)"
else
  fail "EBS default encryption is NOT enabled — new volumes created unencrypted by default"
fi

# Check for existing unencrypted volumes
UNENC_VOLS=$(aws ec2 describe-volumes \
  --filters "Name=encrypted,Values=false" \
  --query 'Volumes[*].[VolumeId,State,Attachments[0].InstanceId]' \
  --output text 2>/dev/null || echo "")
if [[ -z "$UNENC_VOLS" ]]; then
  pass "No unencrypted EBS volumes found"
else
  fail "Unencrypted EBS volumes exist:"
  while read -r VOL_ID STATE INST_ID; do
    info "  $VOL_ID | $STATE | attached to: ${INST_ID:-detached}"
  done <<< "$UNENC_VOLS"
fi

section "EC2 — Unused Key Pairs"

KEY_PAIRS=$(aws ec2 describe-key-pairs \
  --query 'KeyPairs[*].KeyName' --output text 2>/dev/null || echo "")
KEY_COUNT=$(echo "$KEY_PAIRS" | wc -w | tr -d ' ')
info "$KEY_COUNT key pair(s) registered"

# Find which key pairs are in use
USED_KEYS=$(aws ec2 describe-instances \
  --filters "Name=instance-state-name,Values=running" \
  --query 'Reservations[*].Instances[*].KeyName' \
  --output text 2>/dev/null | sort -u)

for KEY in $KEY_PAIRS; do
  if echo "$USED_KEYS" | grep -q "^${KEY}$"; then
    info "  Key '$KEY': in use"
  else
    warn "  Key '$KEY': NOT attached to any running instance (review if needed)"
  fi
done

section "EC2 — Systems Manager (SSM) Agent Coverage"

SSM_INSTANCES=$(aws ssm describe-instance-information \
  --query 'InstanceInformationList[?PingStatus==`Online`].InstanceId' \
  --output text 2>/dev/null || echo "")

RUNNING_IDS=$(aws ec2 describe-instances \
  --filters "Name=instance-state-name,Values=running" \
  --query 'Reservations[*].Instances[*].InstanceId' \
  --output text 2>/dev/null || echo "")

NO_SSM=()
for INST_ID in $RUNNING_IDS; do
  if ! echo "$SSM_INSTANCES" | grep -q "$INST_ID"; then
    NO_SSM+=("$INST_ID")
  fi
done

if [[ ${#NO_SSM[@]} -eq 0 ]]; then
  pass "All running instances are reachable via SSM (no need for SSH)"
else
  warn "Instances NOT registered with SSM (may require SSH key access): ${NO_SSM[*]}"
fi

section "EC2 — Public EBS Snapshots"

PUBLIC_SNAPS=$(aws ec2 describe-snapshots \
  --owner-ids self \
  --filters "Name=status,Values=completed" \
  --query 'Snapshots[?Public==`true`].[SnapshotId,StartTime]' \
  --output text 2>/dev/null || echo "")
if [[ -z "$PUBLIC_SNAPS" ]]; then
  pass "No public EBS snapshots"
else
  fail "PUBLIC EBS snapshots (visible to all AWS accounts):"
  while read -r SNAP_ID TIME; do
    info "  $SNAP_ID (created: $TIME)"
  done <<< "$PUBLIC_SNAPS"
fi

# ════════════════════════════════════════════════════════════
# LAMBDA
# ════════════════════════════════════════════════════════════
section "Lambda — Security Checks"

FUNCTIONS=$(aws lambda list-functions \
  --query 'Functions[*].FunctionName' --output text 2>/dev/null || echo "")

if [[ -z "$FUNCTIONS" ]]; then
  info "No Lambda functions found"
else
  SECRET_PATTERNS='(PASSWORD|SECRET|KEY|TOKEN|CREDENTIAL|DB_PASS|API_KEY|PRIVATE)'

  SECRETS_IN_ENV=()
  NO_VPC_FUNCTIONS=()
  WIDE_OPEN_URLS=()

  for FN in $FUNCTIONS; do
    FN_CONFIG=$(aws lambda get-function-configuration --function-name "$FN" \
      --output json 2>/dev/null || echo "{}")

    echo -e "  ${CYAN}Function:${NC} $FN"

    # 1. Environment variable secrets
    ENV_VARS=$(echo "$FN_CONFIG" | python3 -c "
import sys, json, re
d = json.load(sys.stdin)
env = d.get('Environment', {}).get('Variables', {})
pattern = re.compile(r'PASSWORD|SECRET|KEY|TOKEN|CREDENTIAL|DB_PASS|API_KEY|PRIVATE', re.I)
suspicious = [k for k in env if pattern.search(k)]
if suspicious:
    print(' '.join(suspicious))
" 2>/dev/null || echo "")
    if [[ -n "$ENV_VARS" ]]; then
      SECRETS_IN_ENV+=("$FN($ENV_VARS)")
      echo -e "    ${RED}[FAIL]${NC} Suspicious env vars (may contain secrets): $ENV_VARS"
    else
      echo -e "    ${GREEN}[PASS]${NC} No suspicious env var names"
    fi

    # 2. VPC configuration
    VPC_ID=$(echo "$FN_CONFIG" | python3 -c "import sys,json; \
      print(json.load(sys.stdin).get('VpcConfig',{}).get('VpcId',''))" 2>/dev/null || echo "")
    if [[ -n "$VPC_ID" && "$VPC_ID" != "None" ]]; then
      echo -e "    ${GREEN}[PASS]${NC} Deployed in VPC: $VPC_ID"
    else
      NO_VPC_FUNCTIONS+=("$FN")
      echo -e "    ${YELLOW}[WARN]${NC} Not deployed in VPC (public internet access)"
    fi

    # 3. Function URL auth type
    FN_URL=$(aws lambda get-function-url-config --function-name "$FN" 2>/dev/null || echo "")
    if [[ -n "$FN_URL" ]]; then
      AUTH_TYPE=$(echo "$FN_URL" | python3 -c "import sys,json; \
        print(json.load(sys.stdin).get('AuthType',''))" 2>/dev/null || echo "")
      if [[ "$AUTH_TYPE" == "NONE" ]]; then
        WIDE_OPEN_URLS+=("$FN")
        echo -e "    ${RED}[FAIL]${NC} Function URL configured with AuthType: NONE (no auth!)"
      elif [[ "$AUTH_TYPE" == "AWS_IAM" ]]; then
        echo -e "    ${GREEN}[PASS]${NC} Function URL: AuthType=AWS_IAM"
      fi
    fi

    # 4. Runtime — check for deprecated
    RUNTIME=$(echo "$FN_CONFIG" | python3 -c "import sys,json; \
      print(json.load(sys.stdin).get('Runtime','unknown'))" 2>/dev/null || echo "unknown")
    DEPRECATED_RUNTIMES="nodejs12.x nodejs10.x python2.7 python3.6 ruby2.5 dotnetcore2.1"
    if echo "$DEPRECATED_RUNTIMES" | grep -q "$RUNTIME"; then
      echo -e "    ${RED}[FAIL]${NC} Deprecated runtime: $RUNTIME — upgrade immediately"
      fail "$FN: deprecated runtime $RUNTIME"
    else
      echo -e "    ${GREEN}[PASS]${NC} Runtime: $RUNTIME"
    fi

    echo ""
  done

  [[ ${#SECRETS_IN_ENV[@]} -eq 0 ]] \
    && pass "No Lambda functions with secret-like env var names" \
    || fail "Lambda functions with potential secrets in env vars: ${SECRETS_IN_ENV[*]}"

  [[ ${#WIDE_OPEN_URLS[@]} -eq 0 ]] \
    && pass "No Lambda Function URLs with NONE auth type" \
    || fail "Unauthenticated Lambda Function URLs: ${WIDE_OPEN_URLS[*]}"

  [[ ${#NO_VPC_FUNCTIONS[@]} -eq 0 ]] \
    && pass "All Lambda functions deployed in VPC" \
    || warn "Lambda functions outside VPC: ${NO_VPC_FUNCTIONS[*]}"
fi

# ════════════════════════════════════════════════════════════
# ECS
# ════════════════════════════════════════════════════════════
section "ECS — Privileged Containers & Task Roles"

CLUSTERS=$(aws ecs list-clusters \
  --query 'clusterArns[*]' --output text 2>/dev/null || echo "")

if [[ -z "$CLUSTERS" ]]; then
  info "No ECS clusters found"
else
  PRIVILEGED_TASKS=()
  NO_TASK_ROLE_TASKS=()

  for CLUSTER_ARN in $CLUSTERS; do
    CLUSTER_NAME=$(basename "$CLUSTER_ARN")
    info "Checking ECS cluster: $CLUSTER_NAME"

    TASK_DEFS=$(aws ecs list-task-definitions \
      --status ACTIVE \
      --query 'taskDefinitionArns[*]' \
      --output text 2>/dev/null | head -c 2000 || echo "")

    for TASK_ARN in $TASK_DEFS; do
      TASK_DEF=$(aws ecs describe-task-definition \
        --task-definition "$TASK_ARN" \
        --query 'taskDefinition' --output json 2>/dev/null || echo "{}")

      TASK_FAMILY=$(echo "$TASK_DEF" | python3 -c "import sys,json; \
        print(json.load(sys.stdin).get('family',''))" 2>/dev/null || echo "")

      # Check for privileged containers
      HAS_PRIV=$(echo "$TASK_DEF" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for c in d.get('containerDefinitions', []):
    if c.get('privileged', False):
        print(c.get('name', 'unknown'))
" 2>/dev/null || echo "")
      if [[ -n "$HAS_PRIV" ]]; then
        PRIVILEGED_TASKS+=("$TASK_FAMILY(container:$HAS_PRIV)")
        echo -e "  ${RED}[FAIL]${NC} Task $TASK_FAMILY has privileged container: $HAS_PRIV"
      fi

      # Check for task role
      TASK_ROLE=$(echo "$TASK_DEF" | python3 -c "import sys,json; \
        print(json.load(sys.stdin).get('taskRoleArn',''))" 2>/dev/null || echo "")
      if [[ -z "$TASK_ROLE" ]]; then
        NO_TASK_ROLE_TASKS+=("$TASK_FAMILY")
      fi

      # Check for secrets in environment (plaintext)
      PLAIN_SECRETS=$(echo "$TASK_DEF" | python3 -c "
import sys, json, re
d = json.load(sys.stdin)
pattern = re.compile(r'PASSWORD|SECRET|KEY|TOKEN|CREDENTIAL', re.I)
found = []
for c in d.get('containerDefinitions', []):
    for e in c.get('environment', []):
        if pattern.search(e.get('name','')):
            found.append(f\"{c['name']}.{e['name']}\")
if found:
    print(' '.join(found))
" 2>/dev/null || echo "")
      if [[ -n "$PLAIN_SECRETS" ]]; then
        echo -e "  ${RED}[FAIL]${NC} Task $TASK_FAMILY: secrets in plaintext environment: $PLAIN_SECRETS"
        fail "$TASK_FAMILY: plaintext secrets in container env vars"
      fi
    done
  done

  [[ ${#PRIVILEGED_TASKS[@]} -eq 0 ]] \
    && pass "No ECS tasks running privileged containers" \
    || fail "Privileged ECS containers: ${PRIVILEGED_TASKS[*]}"

  [[ ${#NO_TASK_ROLE_TASKS[@]} -eq 0 ]] \
    && pass "All ECS task definitions have a task role" \
    || warn "ECS tasks without task role (using node instance profile): ${NO_TASK_ROLE_TASKS[*]}"
fi

# ════════════════════════════════════════════════════════════
# EKS
# ════════════════════════════════════════════════════════════
section "EKS — Cluster Security Checks"

EKS_CLUSTERS=$(aws eks list-clusters \
  --query 'clusters[*]' --output text 2>/dev/null || echo "")

if [[ -z "$EKS_CLUSTERS" ]]; then
  info "No EKS clusters found"
else
  for CLUSTER in $EKS_CLUSTERS; do
    echo -e "  ${CYAN}Cluster:${NC} $CLUSTER"
    CLUSTER_INFO=$(aws eks describe-cluster --name "$CLUSTER" \
      --query 'cluster' --output json 2>/dev/null || echo "{}")

    # 1. API server endpoint access
    PUB_ACCESS=$(echo "$CLUSTER_INFO" | python3 -c "import sys,json; \
      print(json.load(sys.stdin).get('resourcesVpcConfig',{}).get('endpointPublicAccess',True))" 2>/dev/null || echo True)
    PRIV_ACCESS=$(echo "$CLUSTER_INFO" | python3 -c "import sys,json; \
      print(json.load(sys.stdin).get('resourcesVpcConfig',{}).get('endpointPrivateAccess',False))" 2>/dev/null || echo False)
    PUB_CIDRS=$(echo "$CLUSTER_INFO" | python3 -c "import sys,json; \
      print(json.load(sys.stdin).get('resourcesVpcConfig',{}).get('publicAccessCidrs',[]))" 2>/dev/null || echo "[]")

    if [[ "$PUB_ACCESS" == "False" ]]; then
      echo -e "    ${GREEN}[PASS]${NC} API server: public access disabled (private only)"
    elif [[ "$PUB_CIDRS" == "['0.0.0.0/0']" || "$PUB_CIDRS" == "['::/0']" ]]; then
      echo -e "    ${RED}[FAIL]${NC} API server: public access open to 0.0.0.0/0"
      fail "$CLUSTER: EKS API open to 0.0.0.0/0"
    else
      echo -e "    ${YELLOW}[WARN]${NC} API server: public but restricted to $PUB_CIDRS — verify only VPN/corp IPs"
    fi

    if [[ "$PRIV_ACCESS" == "True" ]]; then
      echo -e "    ${GREEN}[PASS]${NC} API server: private access enabled"
    else
      echo -e "    ${YELLOW}[WARN]${NC} API server: private access disabled"
    fi

    # 2. Secrets encryption
    ENC_CONFIG=$(echo "$CLUSTER_INFO" | python3 -c "import sys,json; \
      enc=json.load(sys.stdin).get('encryptionConfig',[]); \
      print('YES' if enc else 'NO')" 2>/dev/null || echo NO)
    if [[ "$ENC_CONFIG" == "YES" ]]; then
      echo -e "    ${GREEN}[PASS]${NC} Kubernetes secrets encrypted with KMS"
    else
      echo -e "    ${RED}[FAIL]${NC} Kubernetes secrets NOT encrypted with KMS (envelope encryption)"
      fail "$CLUSTER: no KMS encryption for Kubernetes secrets"
    fi

    # 3. Audit logging
    LOGGING=$(echo "$CLUSTER_INFO" | python3 -c "
import sys, json
d = json.load(sys.stdin)
enabled = [l['types'] for l in d.get('logging',{}).get('clusterLogging',[]) if l.get('enabled')]
enabled_flat = [t for types in enabled for t in types]
print(' '.join(enabled_flat) if enabled_flat else 'NONE')
" 2>/dev/null || echo "NONE")
    REQUIRED_LOGS=("api" "audit" "authenticator")
    MISSING_LOGS=()
    for LOG_TYPE in "${REQUIRED_LOGS[@]}"; do
      echo "$LOGGING" | grep -q "$LOG_TYPE" || MISSING_LOGS+=("$LOG_TYPE")
    done
    if [[ ${#MISSING_LOGS[@]} -eq 0 ]]; then
      echo -e "    ${GREEN}[PASS]${NC} Logging: $LOGGING"
    else
      echo -e "    ${RED}[FAIL]${NC} Missing critical log types: ${MISSING_LOGS[*]} (enabled: $LOGGING)"
      fail "$CLUSTER: missing EKS log types: ${MISSING_LOGS[*]}"
    fi

    # 4. Kubernetes version
    K8S_VERSION=$(echo "$CLUSTER_INFO" | python3 -c "import sys,json; \
      print(json.load(sys.stdin).get('version','unknown'))" 2>/dev/null || echo "unknown")
    echo -e "    ${CYAN}[INFO]${NC} Kubernetes version: $K8S_VERSION (verify not EOL)"

    echo ""
  done
fi

print_summary "Compute Security"
write_json_summary "05-compute"
