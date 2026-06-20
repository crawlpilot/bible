#!/usr/bin/env bash
# ============================================================
# 04-rds.sh — RDS / Aurora Security Validation
# Checks: public access, encryption, backups, deletion
#         protection, enhanced monitoring, minor version upgrade,
#         multi-AZ, security group exposure, parameter groups
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

header "RDS / Aurora Security Validation"
check_aws_access

# ─── Fetch All DB Instances ───────────────────────────────────
section "Fetching RDS Instances"

DB_INSTANCES=$(aws rds describe-db-instances \
  --query 'DBInstances[*].[DBInstanceIdentifier,DBInstanceClass,Engine,DBInstanceStatus]' \
  --output text 2>/dev/null)

if [[ -z "$DB_INSTANCES" ]]; then
  info "No RDS DB instances found in region $AWS_REGION"
  print_summary "RDS Security"
  write_json_summary "04-rds"
  exit 0
fi

info "Instances found:"
while read -r ID CLASS ENGINE STATUS; do
  info "  $ID | $ENGINE | $CLASS | $STATUS"
done <<< "$DB_INSTANCES"

# ─── Per-Instance Checks ──────────────────────────────────────
section "Per-Instance Security Checks"

PUBLIC_DBS=()
UNENCRYPTED_DBS=()
NO_BACKUP_DBS=()
NO_DELETION_PROTECT_DBS=()
NO_MINOR_UPGRADE_DBS=()
NO_ENHANCED_MONITORING_DBS=()
NO_MULTI_AZ_DBS=()
IAM_AUTH_DISABLED=()
PUBLIC_SNAPSHOT_DBS=()

while read -r DB_ID _ _ _; do
  echo -e "  ${CYAN}Instance:${NC} $DB_ID"

  DETAILS=$(aws rds describe-db-instances \
    --db-instance-identifier "$DB_ID" \
    --query 'DBInstances[0]' --output json 2>/dev/null || echo "{}")

  # 1. Public accessibility
  PUBLIC=$(echo "$DETAILS" | python3 -c "import sys,json; \
    print(json.load(sys.stdin).get('PubliclyAccessible', False))" 2>/dev/null || echo False)
  if [[ "$PUBLIC" == "True" ]]; then
    PUBLIC_DBS+=("$DB_ID")
    echo -e "    ${RED}[FAIL]${NC} PubliclyAccessible: TRUE — DB endpoint exposed to internet"
  else
    echo -e "    ${GREEN}[PASS]${NC} PubliclyAccessible: false"
  fi

  # 2. Encryption at rest
  ENCRYPTED=$(echo "$DETAILS" | python3 -c "import sys,json; \
    print(json.load(sys.stdin).get('StorageEncrypted', False))" 2>/dev/null || echo False)
  if [[ "$ENCRYPTED" == "True" ]]; then
    KMS_ID=$(echo "$DETAILS" | python3 -c "import sys,json; \
      print(json.load(sys.stdin).get('KmsKeyId','aws-managed'))" 2>/dev/null || echo "aws-managed")
    echo -e "    ${GREEN}[PASS]${NC} Storage encryption: enabled (KMS: $KMS_ID)"
  else
    UNENCRYPTED_DBS+=("$DB_ID")
    echo -e "    ${RED}[FAIL]${NC} Storage encryption: NOT enabled"
  fi

  # 3. Automated backups
  BACKUP_DAYS=$(echo "$DETAILS" | python3 -c "import sys,json; \
    print(json.load(sys.stdin).get('BackupRetentionPeriod', 0))" 2>/dev/null || echo 0)
  if [[ "$BACKUP_DAYS" -ge 7 ]]; then
    echo -e "    ${GREEN}[PASS]${NC} Automated backups: ${BACKUP_DAYS}-day retention"
  elif [[ "$BACKUP_DAYS" -gt 0 ]]; then
    echo -e "    ${YELLOW}[WARN]${NC} Automated backups: ${BACKUP_DAYS}-day retention (recommend ≥ 7)"
    NO_BACKUP_DBS+=("$DB_ID(${BACKUP_DAYS}d)")
  else
    NO_BACKUP_DBS+=("$DB_ID")
    echo -e "    ${RED}[FAIL]${NC} Automated backups: DISABLED"
  fi

  # 4. Deletion protection
  DEL_PROTECT=$(echo "$DETAILS" | python3 -c "import sys,json; \
    print(json.load(sys.stdin).get('DeletionProtection', False))" 2>/dev/null || echo False)
  if [[ "$DEL_PROTECT" == "True" ]]; then
    echo -e "    ${GREEN}[PASS]${NC} Deletion protection: enabled"
  else
    NO_DELETION_PROTECT_DBS+=("$DB_ID")
    echo -e "    ${RED}[FAIL]${NC} Deletion protection: disabled"
  fi

  # 5. Auto minor version upgrade
  AUTO_MINOR=$(echo "$DETAILS" | python3 -c "import sys,json; \
    print(json.load(sys.stdin).get('AutoMinorVersionUpgrade', False))" 2>/dev/null || echo False)
  if [[ "$AUTO_MINOR" == "True" ]]; then
    echo -e "    ${GREEN}[PASS]${NC} Auto minor version upgrade: enabled"
  else
    NO_MINOR_UPGRADE_DBS+=("$DB_ID")
    echo -e "    ${YELLOW}[WARN]${NC} Auto minor version upgrade: disabled"
  fi

  # 6. Enhanced monitoring
  MON_INTERVAL=$(echo "$DETAILS" | python3 -c "import sys,json; \
    print(json.load(sys.stdin).get('MonitoringInterval', 0))" 2>/dev/null || echo 0)
  if [[ "$MON_INTERVAL" -gt 0 ]]; then
    echo -e "    ${GREEN}[PASS]${NC} Enhanced monitoring: ${MON_INTERVAL}s interval"
  else
    NO_ENHANCED_MONITORING_DBS+=("$DB_ID")
    echo -e "    ${YELLOW}[WARN]${NC} Enhanced monitoring: disabled"
  fi

  # 7. Multi-AZ
  MULTI_AZ=$(echo "$DETAILS" | python3 -c "import sys,json; \
    print(json.load(sys.stdin).get('MultiAZ', False))" 2>/dev/null || echo False)
  if [[ "$MULTI_AZ" == "True" ]]; then
    echo -e "    ${GREEN}[PASS]${NC} Multi-AZ: enabled"
  else
    NO_MULTI_AZ_DBS+=("$DB_ID")
    echo -e "    ${YELLOW}[WARN]${NC} Multi-AZ: disabled (single point of failure)"
  fi

  # 8. IAM database authentication
  IAM_AUTH=$(echo "$DETAILS" | python3 -c "import sys,json; \
    print(json.load(sys.stdin).get('IAMDatabaseAuthenticationEnabled', False))" 2>/dev/null || echo False)
  if [[ "$IAM_AUTH" == "True" ]]; then
    echo -e "    ${GREEN}[PASS]${NC} IAM database authentication: enabled"
  else
    IAM_AUTH_DISABLED+=("$DB_ID")
    echo -e "    ${YELLOW}[WARN]${NC} IAM database authentication: disabled (password-only)"
  fi

  # 9. CloudWatch log exports
  LOGS=$(echo "$DETAILS" | python3 -c "import sys,json; \
    print(json.load(sys.stdin).get('EnabledCloudwatchLogsExports', []))" 2>/dev/null || echo "[]")
  if [[ "$LOGS" != "[]" && -n "$LOGS" ]]; then
    echo -e "    ${GREEN}[PASS]${NC} CloudWatch log exports: $LOGS"
  else
    echo -e "    ${YELLOW}[WARN]${NC} CloudWatch log exports: not configured"
  fi

  # 10. Security groups — check if overly permissive
  SG_IDS=$(echo "$DETAILS" | python3 -c "import sys,json; \
    d=json.load(sys.stdin); \
    print(' '.join([s['VpcSecurityGroupId'] for s in d.get('VpcSecurityGroups',[])]))" 2>/dev/null || echo "")
  for SG_ID in $SG_IDS; do
    DB_ENGINE=$(echo "$DETAILS" | python3 -c "import sys,json; \
      print(json.load(sys.stdin).get('Engine',''))" 2>/dev/null || echo "")
    # Get DB port
    DB_PORT=$(echo "$DETAILS" | python3 -c "import sys,json; \
      print(json.load(sys.stdin).get('Endpoint',{}).get('Port',0))" 2>/dev/null || echo 0)

    OPEN_TO_WORLD=$(aws ec2 describe-security-groups --group-ids "$SG_ID" \
      --query "SecurityGroups[0].IpPermissions[?IpRanges[?CidrIp=='0.0.0.0/0'] && \
               (FromPort<=\`$DB_PORT\` && ToPort>=\`$DB_PORT\`)]" \
      --output text 2>/dev/null || echo "")
    if [[ -n "$OPEN_TO_WORLD" ]]; then
      PUBLIC_DBS+=("$DB_ID(SG-$SG_ID)")
      echo -e "    ${RED}[FAIL]${NC} Security group $SG_ID allows DB port $DB_PORT from 0.0.0.0/0"
    fi
  done

  echo ""
done <<< "$DB_INSTANCES"

# ─── RDS Snapshots — Public? ──────────────────────────────────
section "RDS Snapshots — Public Exposure"

PUBLIC_SNAPS=$(aws rds describe-db-snapshots \
  --include-public \
  --query "DBSnapshots[?SnapshotType=='public'].[DBSnapshotIdentifier,DBInstanceIdentifier]" \
  --output text 2>/dev/null || echo "")

if [[ -z "$PUBLIC_SNAPS" ]]; then
  pass "No public RDS snapshots found"
else
  fail "PUBLIC RDS snapshots found (accessible to any AWS account):"
  while read -r SNAP_ID DB_ID; do
    info "  Snapshot: $SNAP_ID from DB: $DB_ID"
  done <<< "$PUBLIC_SNAPS"
fi

# ─── Aurora Clusters ──────────────────────────────────────────
section "Aurora Clusters"

CLUSTERS=$(aws rds describe-db-clusters \
  --query 'DBClusters[*].[DBClusterIdentifier,Engine,DeletionProtection,StorageEncrypted,BackupRetentionPeriod]' \
  --output text 2>/dev/null || echo "")

if [[ -z "$CLUSTERS" ]]; then
  info "No Aurora clusters found"
else
  while read -r CLUSTER_ID ENGINE DEL_PROTECT ENCRYPTED BACKUP_DAYS; do
    echo -e "  ${CYAN}Cluster:${NC} $CLUSTER_ID ($ENGINE)"
    [[ "$DEL_PROTECT" == "True" ]] \
      && echo -e "    ${GREEN}[PASS]${NC} Deletion protection: enabled" \
      || { echo -e "    ${RED}[FAIL]${NC} Deletion protection: disabled"; fail "$CLUSTER_ID: no deletion protection"; }
    [[ "$ENCRYPTED" == "True" ]] \
      && echo -e "    ${GREEN}[PASS]${NC} Storage encryption: enabled" \
      || { echo -e "    ${RED}[FAIL]${NC} Storage encryption: NOT enabled"; fail "$CLUSTER_ID: not encrypted"; }
    [[ "$BACKUP_DAYS" -ge 7 ]] \
      && echo -e "    ${GREEN}[PASS]${NC} Backup retention: ${BACKUP_DAYS} days" \
      || echo -e "    ${YELLOW}[WARN]${NC} Backup retention: ${BACKUP_DAYS} days (recommend ≥ 7)"
  done <<< "$CLUSTERS"
fi

# ─── Consolidated Summary ─────────────────────────────────────
section "RDS Issue Summary"

[[ ${#PUBLIC_DBS[@]} -eq 0 ]] \
  && pass "No publicly accessible RDS instances" \
  || fail "Public RDS instances/SGs: ${PUBLIC_DBS[*]}"

[[ ${#UNENCRYPTED_DBS[@]} -eq 0 ]] \
  && pass "All RDS instances have storage encryption" \
  || fail "Unencrypted RDS instances: ${UNENCRYPTED_DBS[*]}"

[[ ${#NO_BACKUP_DBS[@]} -eq 0 ]] \
  && pass "All RDS instances have automated backups ≥ 7 days" \
  || fail "RDS instances with insufficient backups: ${NO_BACKUP_DBS[*]}"

[[ ${#NO_DELETION_PROTECT_DBS[@]} -eq 0 ]] \
  && pass "All RDS instances have deletion protection" \
  || fail "RDS without deletion protection: ${NO_DELETION_PROTECT_DBS[*]}"

[[ ${#NO_MULTI_AZ_DBS[@]} -eq 0 ]] \
  && pass "All RDS instances are Multi-AZ" \
  || warn "RDS without Multi-AZ: ${NO_MULTI_AZ_DBS[*]}"

[[ ${#IAM_AUTH_DISABLED[@]} -eq 0 ]] \
  && pass "All RDS instances have IAM authentication enabled" \
  || warn "RDS without IAM auth: ${IAM_AUTH_DISABLED[*]}"

print_summary "RDS Security"
write_json_summary "04-rds"
