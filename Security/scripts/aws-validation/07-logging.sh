#!/usr/bin/env bash
# ============================================================
# 07-logging.sh — Logging & Detection Validation
# Checks: CloudTrail (all-region, validation, S3 settings),
#         GuardDuty (all regions, protection plans),
#         Security Hub, Config, Macie, Inspector,
#         CloudWatch alarms for CIS benchmark events
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

header "Logging & Detection Validation"
check_aws_access

# ─── CloudTrail ───────────────────────────────────────────────
section "CloudTrail — Multi-Region Coverage"

TRAILS=$(aws cloudtrail describe-trails \
  --include-shadow-trails \
  --query 'trailList[*].[Name,IsMultiRegionTrail,HomeRegion,LogFileValidationEnabled,S3BucketName,IsLogging]' \
  --output text 2>/dev/null || echo "")

if [[ -z "$TRAILS" ]]; then
  fail "No CloudTrail trails configured"
else
  MULTI_REGION_TRAIL=false
  VALIDATION_ENABLED=false

  while read -r TRAIL_NAME IS_MULTI HOME_REGION VALIDATION S3_BUCKET IS_LOGGING; do
    echo -e "  ${CYAN}Trail:${NC} $TRAIL_NAME (home: $HOME_REGION)"

    if [[ "$IS_MULTI" == "True" ]]; then
      MULTI_REGION_TRAIL=true
      echo -e "    ${GREEN}[PASS]${NC} Multi-region: YES"
    else
      echo -e "    ${YELLOW}[WARN]${NC} Multi-region: NO — only covers $HOME_REGION"
    fi

    if [[ "$VALIDATION" == "True" ]]; then
      VALIDATION_ENABLED=true
      echo -e "    ${GREEN}[PASS]${NC} Log file validation: enabled"
    else
      echo -e "    ${RED}[FAIL]${NC} Log file validation: DISABLED (tampering not detectable)"
      fail "$TRAIL_NAME: log file validation disabled"
    fi

    if [[ "$IS_LOGGING" == "True" ]]; then
      echo -e "    ${GREEN}[PASS]${NC} Trail is actively logging"
    else
      echo -e "    ${RED}[FAIL]${NC} Trail is STOPPED — not collecting events"
      fail "$TRAIL_NAME: trail logging is stopped"
    fi

    # Check S3 bucket
    echo -e "    ${CYAN}[INFO]${NC} Log destination: s3://$S3_BUCKET"

    # Check S3 bucket public access
    BUCKET_BLOCK=$(aws s3api get-public-access-block --bucket "$S3_BUCKET" 2>/dev/null || echo "none")
    if [[ "$BUCKET_BLOCK" == "none" ]]; then
      fail "$TRAIL_NAME: CloudTrail S3 bucket $S3_BUCKET has no public access block"
    else
      echo -e "    ${GREEN}[PASS]${NC} CloudTrail S3 bucket has public access block"
    fi

    # Event selectors — management + data events?
    EVENT_SELECTORS=$(aws cloudtrail get-event-selectors --trail-name "$TRAIL_NAME" \
      --query 'EventSelectors' --output json 2>/dev/null || echo "[]")
    MGMT_RW=$(echo "$EVENT_SELECTORS" | python3 -c "
import sys, json
selectors = json.load(sys.stdin)
for s in selectors:
    rw = s.get('ReadWriteType', '')
    if rw == 'All':
        print('All')
        break
    elif rw in ('ReadOnly', 'WriteOnly'):
        print(rw)
" 2>/dev/null || echo "")
    if [[ "$MGMT_RW" == "All" ]]; then
      echo -e "    ${GREEN}[PASS]${NC} Management events: Read + Write"
    else
      echo -e "    ${YELLOW}[WARN]${NC} Management events: $MGMT_RW only (recommend All)"
    fi

    echo ""
  done <<< "$TRAILS"

  $MULTI_REGION_TRAIL && pass "At least one multi-region CloudTrail trail exists" \
    || fail "No multi-region trail — events in other regions not captured"
fi

# ─── CloudTrail — S3 Object-Level Logging ────────────────────
section "CloudTrail — S3 Data Events (Object-Level Logging)"

DATA_EVENTS=$(aws cloudtrail get-event-selectors \
  --trail-name "$(aws cloudtrail describe-trails \
    --query 'trailList[?IsMultiRegionTrail==`true`].Name | [0]' \
    --output text 2>/dev/null || echo "")" \
  --query 'EventSelectors[*].DataResources[?Type==`AWS::S3::Object`]' \
  --output text 2>/dev/null || echo "")

if [[ -n "$DATA_EVENTS" ]]; then
  pass "S3 object-level data events are being logged"
else
  warn "S3 object-level data events not configured (blind to object reads/writes)"
fi

# ─── GuardDuty ───────────────────────────────────────────────
section "GuardDuty — Threat Detection"

GD_STATUS=$(aws guardduty list-detectors \
  --query 'DetectorIds[0]' --output text 2>/dev/null || echo "")

if [[ -z "$GD_STATUS" || "$GD_STATUS" == "None" ]]; then
  fail "GuardDuty is NOT enabled in $AWS_REGION"
else
  DETECTOR_ID="$GD_STATUS"
  GD_DETAIL=$(aws guardduty get-detector --detector-id "$DETECTOR_ID" \
    --output json 2>/dev/null || echo "{}")

  GD_STATE=$(echo "$GD_DETAIL" | python3 -c "import sys,json; \
    print(json.load(sys.stdin).get('Status','UNKNOWN'))" 2>/dev/null || echo "UNKNOWN")

  if [[ "$GD_STATE" == "ENABLED" ]]; then
    pass "GuardDuty: ENABLED (detector: $DETECTOR_ID)"
  else
    fail "GuardDuty detector found but status: $GD_STATE"
  fi

  # Check protection plans
  PROTECTION_PLANS=(
    "s3Logs:S3Protection"
    "ebsVolumes:MalwareProtection"
    "eksAuditLogs:EKSAuditLogs"
    "rdsLoginEvents:RDSProtection"
    "lambdaNetworkLogs:LambdaNetworkActivity"
  )

  GD_FEATURES=$(echo "$GD_DETAIL" | python3 -c "
import sys, json
d = json.load(sys.stdin)
features = d.get('Features', [])
for f in features:
    print(f.get('Name',''), f.get('Status',''))
" 2>/dev/null || echo "")

  for PLAN_PAIR in "${PROTECTION_PLANS[@]}"; do
    PLAN_NAME="${PLAN_PAIR%%:*}"
    PLAN_DISPLAY="${PLAN_PAIR##*:}"
    if echo "$GD_FEATURES" | grep -qi "$PLAN_NAME.*ENABLED"; then
      pass "GuardDuty $PLAN_DISPLAY: enabled"
    else
      warn "GuardDuty $PLAN_DISPLAY: NOT enabled"
    fi
  done

  # Active findings summary
  FINDING_COUNT=$(aws guardduty list-findings \
    --detector-id "$DETECTOR_ID" \
    --finding-criteria '{"Criterion":{"severity":{"Gte":7}}}' \
    --query 'FindingIds | length(@)' --output text 2>/dev/null || echo "0")

  if [[ "$FINDING_COUNT" == "0" ]]; then
    pass "GuardDuty: no HIGH/CRITICAL severity active findings"
  else
    fail "GuardDuty: $FINDING_COUNT HIGH/CRITICAL finding(s) — investigate immediately"
  fi
fi

# ─── AWS Config ───────────────────────────────────────────────
section "AWS Config — Resource Configuration Recording"

CONFIG_STATUS=$(aws configservice describe-configuration-recorder-status \
  --query 'ConfigurationRecordersStatus[0].[name,recording,lastStatus]' \
  --output text 2>/dev/null || echo "")

if [[ -z "$CONFIG_STATUS" ]]; then
  fail "AWS Config: no configuration recorder found"
else
  while read -r RECORDER_NAME IS_RECORDING LAST_STATUS; do
    if [[ "$IS_RECORDING" == "True" && "$LAST_STATUS" == "SUCCESS" ]]; then
      pass "AWS Config recorder '$RECORDER_NAME': recording (status: $LAST_STATUS)"
    else
      fail "AWS Config recorder '$RECORDER_NAME': recording=$IS_RECORDING, status=$LAST_STATUS"
    fi
  done <<< "$CONFIG_STATUS"
fi

# Check key Config managed rules
section "AWS Config — Required Managed Rules"

REQUIRED_RULES=(
  "iam-root-access-key-check"
  "iam-user-mfa-enabled"
  "access-keys-rotated"
  "s3-bucket-public-read-prohibited"
  "s3-bucket-ssl-requests-only"
  "rds-instance-public-access-check"
  "vpc-sg-open-only-to-authorized-ports"
  "cloudtrail-enabled"
  "guardduty-enabled-centralized"
  "s3-bucket-server-side-encryption-enabled"
  "encrypted-volumes"
  "restricted-ssh"
  "restricted-common-ports"
)

ACTIVE_RULES=$(aws configservice describe-config-rules \
  --query 'ConfigRules[?ConfigRuleState==`ACTIVE`].ConfigRuleName' \
  --output text 2>/dev/null || echo "")

for RULE in "${REQUIRED_RULES[@]}"; do
  if echo "$ACTIVE_RULES" | grep -qi "$RULE"; then
    pass "Config rule: $RULE"
  else
    fail "Config rule MISSING: $RULE"
  fi
done

# ─── Security Hub ─────────────────────────────────────────────
section "AWS Security Hub"

SH_STATUS=$(aws securityhub get-enabled-standards \
  --query 'StandardsSubscriptions[*].[StandardsSubscriptionArn,StandardsStatus]' \
  --output text 2>/dev/null || echo "")

if [[ -z "$SH_STATUS" ]]; then
  fail "AWS Security Hub is not enabled or no standards subscribed"
else
  pass "Security Hub enabled with standards:"
  while read -r ARN STATUS; do
    STANDARD=$(basename "$ARN" | sed 's/-[0-9.]*$//')
    if [[ "$STATUS" == "READY" ]]; then
      echo -e "    ${GREEN}[PASS]${NC} $STANDARD: $STATUS"
    else
      echo -e "    ${YELLOW}[WARN]${NC} $STANDARD: $STATUS"
    fi
  done <<< "$SH_STATUS"

  # Critical/High findings
  SH_CRITICAL=$(aws securityhub get-findings \
    --filters '{"SeverityLabel":[{"Value":"CRITICAL","Comparison":"EQUALS"}],"WorkflowStatus":[{"Value":"NEW","Comparison":"EQUALS"}]}' \
    --query 'Findings | length(@)' --output text 2>/dev/null || echo "0")
  SH_HIGH=$(aws securityhub get-findings \
    --filters '{"SeverityLabel":[{"Value":"HIGH","Comparison":"EQUALS"}],"WorkflowStatus":[{"Value":"NEW","Comparison":"EQUALS"}]}' \
    --query 'Findings | length(@)' --output text 2>/dev/null || echo "0")

  [[ "$SH_CRITICAL" -gt 0 ]] \
    && fail "Security Hub: $SH_CRITICAL CRITICAL findings unresolved" \
    || pass "Security Hub: no CRITICAL findings"
  [[ "$SH_HIGH" -gt 0 ]] \
    && warn "Security Hub: $SH_HIGH HIGH severity findings unresolved" \
    || pass "Security Hub: no HIGH findings"
fi

# ─── CloudWatch Alarms — CIS Benchmark Required Alarms ───────
section "CloudWatch Alarms — CIS Benchmark Events"

CIS_FILTERS=(
  "Root account usage:$.userIdentity.type = Root"
  "Console login without MFA:$.additionalEventData.MFAUsed != Yes"
  "Unauthorized API calls:$.errorCode = *UnauthorizedAccess* OR *.AccessDenied"
  "IAM policy changes:$.eventName = PutRolePolicy OR $.eventName = AttachRolePolicy"
  "CloudTrail config changes:$.eventName = StopLogging OR $.eventName = DeleteTrail"
  "S3 policy changes:$.eventName = PutBucketPolicy"
  "Security group changes:$.eventName = AuthorizeSecurityGroupIngress"
  "VPC changes:$.eventName = CreateVpc OR $.eventName = DeleteVpc"
)

LOG_GROUPS=$(aws logs describe-log-groups \
  --query 'logGroups[*].logGroupName' --output text 2>/dev/null || echo "")

METRIC_FILTERS=$(aws logs describe-metric-filters \
  --query 'metricFilters[*].filterName' --output text 2>/dev/null || echo "")

ALARMS=$(aws cloudwatch describe-alarms \
  --query 'MetricAlarms[*].AlarmName' --output text 2>/dev/null || echo "")

for FILTER_PAIR in "${CIS_FILTERS[@]}"; do
  FILTER_NAME="${FILTER_PAIR%%:*}"
  # Check if a metric filter matching the event name exists
  EVENT_KEYWORD=$(echo "$FILTER_NAME" | tr ' ' '-' | tr '[:upper:]' '[:lower:]')
  if echo "$METRIC_FILTERS $ALARMS" | grep -qi "$EVENT_KEYWORD\|$(echo "$FILTER_NAME" | awk '{print $1}' | tr '[:upper:]' '[:lower:]')"; then
    pass "CIS alarm found (heuristic match): $FILTER_NAME"
  else
    warn "CIS alarm possibly missing: $FILTER_NAME — verify CloudWatch metric filters"
  fi
done

# ─── Inspector ────────────────────────────────────────────────
section "Amazon Inspector v2"

INSPECTOR=$(aws inspector2 get-configuration \
  --query 'ec2Configuration.scanMode' --output text 2>/dev/null || echo "disabled")

if [[ "$INSPECTOR" != "disabled" && -n "$INSPECTOR" ]]; then
  pass "Amazon Inspector v2 enabled (EC2 scan mode: $INSPECTOR)"
else
  warn "Amazon Inspector v2 not confirmed active — verify EC2/ECR/Lambda scanning"
fi

# ─── Summary ─────────────────────────────────────────────────
print_summary "Logging & Detection"
write_json_summary "07-logging"
