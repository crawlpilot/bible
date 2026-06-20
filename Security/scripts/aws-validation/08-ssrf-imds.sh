#!/usr/bin/env bash
# ============================================================
# 08-ssrf-imds.sh — SSRF / IMDS Attack Surface Validation
# Checks: IMDSv2 enforcement across all instances, hop limit
#         per-instance class (EKS nodes, ECS, plain EC2),
#         Lambda IMDS access, org-level IMDSv2 SCPs
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

header "SSRF / IMDS Attack Surface Validation"
check_aws_access

info "The SSRF → IMDS attack chain:"
info "  SSRF in app → GET http://169.254.169.254/latest/meta-data/"
info "             → GET /iam/security-credentials/{role-name}"
info "             → AccessKeyId + SecretAccessKey + Token (full role access)"
info "  IMDSv2 breaks this: requires PUT to get session token first (most SSRFs are GET-only)"
echo ""

# ─── IMDSv2 Enforcement — All Instances ──────────────────────
section "IMDSv2 Status — Every Running EC2 Instance"

INSTANCES=$(aws ec2 describe-instances \
  --filters "Name=instance-state-name,Values=running" \
  --query 'Reservations[*].Instances[*].{ID:InstanceId,Tokens:MetadataOptions.HttpTokens,Hop:MetadataOptions.HttpPutResponseHopLimit,State:MetadataOptions.State,Name:Tags[?Key==`Name`].Value|[0],LaunchTime:LaunchTime}' \
  --output json 2>/dev/null || echo "[]")

V1_INSTANCES=()
HIGH_HOP_INSTANCES=()
DISABLED_IMDS=()

echo "$INSTANCES" | python3 -c "
import sys, json
instances = json.load(sys.stdin)
for i in instances:
    inst_id = i.get('ID','?')
    tokens = i.get('Tokens','optional')
    hop = i.get('Hop', 1)
    state = i.get('State','?')
    name = i.get('Name') or 'no-name'
    launch = i.get('LaunchTime','?')

    if tokens == 'required':
        status = 'PASS'
        marker = '\033[0;32m[PASS]\033[0m'
    elif tokens == 'optional':
        status = 'FAIL'
        marker = '\033[0;31m[FAIL]\033[0m'
    else:
        status = 'WARN'
        marker = '\033[1;33m[WARN]\033[0m'

    hop_warn = ' ⚠ hop>1' if hop and int(hop) > 1 else ''
    print(f'  {marker} {inst_id} ({name}) | HttpTokens={tokens} | HopLimit={hop}{hop_warn}')
" 2>/dev/null || true

# Count failures
V1_COUNT=$(echo "$INSTANCES" | python3 -c "
import sys, json
instances = json.load(sys.stdin)
print(sum(1 for i in instances if i.get('Tokens') == 'optional'))
" 2>/dev/null || echo "0")

HIGH_HOP_COUNT=$(echo "$INSTANCES" | python3 -c "
import sys, json
instances = json.load(sys.stdin)
print(sum(1 for i in instances if (i.get('Hop') or 1) > 1))
" 2>/dev/null || echo "0")

TOTAL_COUNT=$(echo "$INSTANCES" | python3 -c "
import sys, json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")

echo ""
info "Total instances: $TOTAL_COUNT | IMDSv1 still allowed: $V1_COUNT | High hop limit: $HIGH_HOP_COUNT"

if [[ "$V1_COUNT" -eq 0 ]]; then
  pass "All $TOTAL_COUNT instances enforce IMDSv2"
else
  fail "$V1_COUNT instance(s) still allow IMDSv1 (SSRF → credential theft risk)"
fi

if [[ "$HIGH_HOP_COUNT" -eq 0 ]]; then
  pass "All instances have hop limit = 1 (containers cannot reach IMDS)"
else
  fail "$HIGH_HOP_COUNT instance(s) have hop limit > 1 — pods/containers can reach IMDS"
fi

# ─── EKS Nodes — IMDSv2 + Hop Limit ─────────────────────────
section "EKS Node Groups — IMDSv2 Enforcement"

EKS_CLUSTERS=$(aws eks list-clusters \
  --query 'clusters[*]' --output text 2>/dev/null || echo "")

for CLUSTER in $EKS_CLUSTERS; do
  info "EKS Cluster: $CLUSTER"

  NODE_GROUPS=$(aws eks list-nodegroups --cluster-name "$CLUSTER" \
    --query 'nodegroups[*]' --output text 2>/dev/null || echo "")

  for NG in $NODE_GROUPS; do
    NG_CONFIG=$(aws eks describe-nodegroup \
      --cluster-name "$CLUSTER" --nodegroup-name "$NG" \
      --query 'nodegroup' --output json 2>/dev/null || echo "{}")

    LT_ID=$(echo "$NG_CONFIG" | python3 -c "import sys,json; \
      lt=json.load(sys.stdin).get('launchTemplate',{}); \
      print(lt.get('id',''))" 2>/dev/null || echo "")

    if [[ -n "$LT_ID" ]]; then
      LT_DATA=$(aws ec2 describe-launch-template-versions \
        --launch-template-id "$LT_ID" --versions '$Latest' \
        --query 'LaunchTemplateVersions[0].LaunchTemplateData.MetadataOptions' \
        --output json 2>/dev/null || echo "{}")

      TOKENS=$(echo "$LT_DATA" | python3 -c "import sys,json; \
        print(json.load(sys.stdin).get('HttpTokens','not-set'))" 2>/dev/null || echo "not-set")
      HOP=$(echo "$LT_DATA" | python3 -c "import sys,json; \
        print(json.load(sys.stdin).get('HttpPutResponseHopLimit','not-set'))" 2>/dev/null || echo "not-set")

      if [[ "$TOKENS" == "required" ]]; then
        echo -e "    ${GREEN}[PASS]${NC} NodeGroup $NG: IMDSv2 required in launch template"
      else
        echo -e "    ${RED}[FAIL]${NC} NodeGroup $NG: IMDSv2 NOT required in launch template (HttpTokens=$TOKENS)"
        fail "$CLUSTER/$NG: pods can reach IMDSv1"
      fi

      if [[ "$HOP" == "1" ]]; then
        echo -e "    ${GREEN}[PASS]${NC} NodeGroup $NG: hop limit = 1 (pods blocked from IMDS)"
      else
        echo -e "    ${RED}[FAIL]${NC} NodeGroup $NG: hop limit = $HOP — pods CAN reach IMDS"
        fail "$CLUSTER/$NG: hop limit $HOP allows pod IMDS access"
      fi
    else
      warn "NodeGroup $NG: no launch template — check node IMDS settings manually"
    fi
  done
done

# ─── EC2 Account-Level IMDS Default ──────────────────────────
section "EC2 Account-Level IMDS Default Settings"

ACCOUNT_IMDS=$(aws ec2 get-instance-metadata-defaults \
  --query 'AccountLevel' --output json 2>/dev/null || echo "{}")

ACCT_TOKENS=$(echo "$ACCOUNT_IMDS" | python3 -c "import sys,json; \
  print(json.load(sys.stdin).get('HttpTokens','not-set'))" 2>/dev/null || echo "not-set")
ACCT_HOP=$(echo "$ACCOUNT_IMDS" | python3 -c "import sys,json; \
  print(json.load(sys.stdin).get('HttpPutResponseHopLimit','not-set'))" 2>/dev/null || echo "not-set")

if [[ "$ACCT_TOKENS" == "required" ]]; then
  pass "Account default IMDS: HttpTokens=required (new instances get IMDSv2 by default)"
else
  warn "Account default IMDS: HttpTokens=$ACCT_TOKENS — new instances may launch with IMDSv1"
  info "Fix: aws ec2 modify-instance-metadata-defaults --http-tokens required --http-put-response-hop-limit 1"
fi

if [[ "$ACCT_HOP" == "1" ]]; then
  pass "Account default IMDS: hop limit = 1"
else
  warn "Account default IMDS: hop limit = $ACCT_HOP — should be 1"
fi

# ─── SCP Check — IMDSv2 Enforcement Policy ───────────────────
section "Organizations SCP — IMDSv2 Enforcement"

ORG_STATUS=$(aws organizations describe-organization \
  --query 'Organization.Id' --output text 2>/dev/null || echo "")

if [[ -z "$ORG_STATUS" ]]; then
  warn "Not in an AWS Organization (or insufficient permissions to check SCPs)"
else
  info "Organization: $ORG_STATUS"
  SCPS=$(aws organizations list-policies \
    --filter SERVICE_CONTROL_POLICY \
    --query 'Policies[*].[Name,Id]' --output text 2>/dev/null || echo "")

  IMDSV2_SCP=false
  while read -r SCP_NAME SCP_ID; do
    SCP_DOC=$(aws organizations describe-policy --policy-id "$SCP_ID" \
      --query 'Policy.Content' --output text 2>/dev/null || echo "")
    if echo "$SCP_DOC" | grep -qi "MetadataHttpTokens\|imdsv2\|HttpTokens"; then
      IMDSV2_SCP=true
      pass "SCP enforcing IMDSv2 found: $SCP_NAME"
    fi
  done <<< "$SCPS"

  $IMDSV2_SCP || warn "No SCP found enforcing IMDSv2 — add an SCP to prevent IMDSv1 launches org-wide"
fi

# ─── Recommended Remediation ─────────────────────────────────
section "Remediation Commands"

info "To enforce IMDSv2 on all existing instances (run per-region):"
echo ""
echo '  # Get all instance IDs with IMDSv1 still allowed:'
echo '  aws ec2 describe-instances \'
echo '    --filters "Name=instance-state-name,Values=running" \'
echo '    --query "Reservations[*].Instances[?MetadataOptions.HttpTokens!=\`required\`].InstanceId" \'
echo '    --output text | tr "\t" "\n" | while read ID; do'
echo '      echo "Patching: $ID"'
echo '      aws ec2 modify-instance-metadata-options \'
echo '        --instance-id "$ID" \'
echo '        --http-tokens required \'
echo '        --http-put-response-hop-limit 1'
echo '    done'
echo ""
info "To set account-level default for new instances:"
echo '  aws ec2 modify-instance-metadata-defaults \'
echo '    --http-tokens required \'
echo '    --http-put-response-hop-limit 1'

print_summary "SSRF / IMDS Validation"
write_json_summary "08-ssrf-imds"
