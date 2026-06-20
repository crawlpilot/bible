#!/usr/bin/env bash
# ============================================================
# 02-network.sh — Network Security Validation
# Checks: Security Groups, VPC Flow Logs, public subnets,
#         NACLs, VPC peering, IGW exposure, endpoint coverage
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

header "Network Security Validation"
check_aws_access

# ─── Security Groups — Dangerous Inbound Rules ───────────────
section "Security Groups — World-Open Dangerous Ports"

DANGEROUS_PORTS_STR="22 3389 3306 5432 1433 27017 6379 9200 9300 2375 2376"
DANGEROUS_PORT_NAMES="22=SSH 3389=RDP 3306=MySQL 5432=PostgreSQL 1433=MSSQL \
27017=MongoDB 6379=Redis 9200=Elasticsearch 9300=ES-cluster 2375=Docker-HTTP 2376=Docker-TLS"

ALL_SGS=$(aws ec2 describe-security-groups \
  --query 'SecurityGroups[*].[GroupId,GroupName,VpcId]' \
  --output text 2>/dev/null)

OPEN_SG_FOUND=false
while read -r SG_ID SG_NAME VPC_ID; do
  RULES=$(aws ec2 describe-security-groups --group-ids "$SG_ID" \
    --query 'SecurityGroups[0].IpPermissions' --output json 2>/dev/null || echo "[]")

  echo "$RULES" | python3 - <<PYEOF 2>/dev/null && OPEN_SG_FOUND=true || true
import json, sys
rules = json.load(sys.stdin)
sg_id = "${SG_ID}"
sg_name = "${SG_NAME}"
dangerous = {22,3389,3306,5432,1433,27017,6379,9200,9300,2375,2376}
found = []
for r in rules:
    from_p = r.get("FromPort", 0)
    to_p = r.get("ToPort", 65535)
    for cidr in r.get("IpRanges", []):
        if cidr.get("CidrIp") in ("0.0.0.0/0",):
            for port in dangerous:
                if from_p <= port <= to_p:
                    found.append(f"port {port} open to 0.0.0.0/0")
    for cidr in r.get("Ipv6Ranges", []):
        if cidr.get("CidrIpv6") in ("::/0",):
            for port in dangerous:
                if from_p <= port <= to_p:
                    found.append(f"port {port} open to ::/0 (IPv6)")
if found:
    for f in found:
        print(f"  FAIL  {sg_id} ({sg_name}) — {f}")
    sys.exit(1)
PYEOF
done <<< "$ALL_SGS"

$OPEN_SG_FOUND && fail "Security groups with dangerous ports open to 0.0.0.0/0 found (see above)" \
  || pass "No security groups expose dangerous ports to 0.0.0.0/0"

# ─── Security Groups — All-Traffic Inbound ───────────────────
section "Security Groups — All-Traffic Inbound (-1 / All)"

ALL_OPEN_SGS=$(aws ec2 describe-security-groups \
  --query "SecurityGroups[?IpPermissions[?IpProtocol=='-1' && IpRanges[?CidrIp=='0.0.0.0/0']]].[GroupId,GroupName]" \
  --output text 2>/dev/null)

if [[ -z "$ALL_OPEN_SGS" ]]; then
  pass "No security groups allow all inbound traffic from 0.0.0.0/0"
else
  fail "Security groups allowing ALL inbound traffic from 0.0.0.0/0:"
  while read -r SG_ID SG_NAME; do
    info "  $SG_ID ($SG_NAME)"
  done <<< "$ALL_OPEN_SGS"
fi

# ─── VPC Flow Logs ────────────────────────────────────────────
section "VPC Flow Logs"

VPCS=$(aws ec2 describe-vpcs --query 'Vpcs[*].VpcId' --output text 2>/dev/null)
NO_FLOW_LOG_VPCS=()
REJECT_ONLY_VPCS=()

for VPC_ID in $VPCS; do
  FL=$(aws ec2 describe-flow-logs \
    --filter "Name=resource-id,Values=$VPC_ID" \
    --query 'FlowLogs[*].[FlowLogId,TrafficType,FlowLogStatus]' \
    --output text 2>/dev/null)

  if [[ -z "$FL" ]]; then
    NO_FLOW_LOG_VPCS+=("$VPC_ID")
  else
    # Check if only REJECT traffic is logged (misses successful lateral movement)
    ALL_TRAFFIC=$(echo "$FL" | grep -c "ALL" || true)
    if [[ "$ALL_TRAFFIC" -eq 0 ]]; then
      REJECT_ONLY_VPCS+=("$VPC_ID")
    fi
  fi
done

if [[ ${#NO_FLOW_LOG_VPCS[@]} -eq 0 ]]; then
  pass "All VPCs have Flow Logs enabled"
else
  fail "VPCs WITHOUT Flow Logs: ${NO_FLOW_LOG_VPCS[*]}"
fi

if [[ ${#REJECT_ONLY_VPCS[@]} -eq 0 ]]; then
  pass "All Flow Logs capture ALL traffic (not just REJECT)"
else
  warn "VPCs with REJECT-only flow logs (misses accepted connections): ${REJECT_ONLY_VPCS[*]}"
fi

# ─── Instances With Public IPs ───────────────────────────────
section "EC2 Instances — Direct Public IP Exposure"

PUBLIC_INSTANCES=$(aws ec2 describe-instances \
  --filters "Name=instance-state-name,Values=running" \
  --query "Reservations[*].Instances[?PublicIpAddress!=null].[InstanceId,PublicIpAddress,Tags[?Key=='Name'].Value|[0]]" \
  --output text 2>/dev/null)

if [[ -z "$PUBLIC_INSTANCES" ]]; then
  pass "No running instances with direct public IP addresses"
else
  warn "Running instances with public IPs (verify these are intentional — load balancers, NAT, bastion):"
  while read -r INST_ID PUB_IP NAME; do
    info "  $INST_ID | $PUB_IP | ${NAME:-<no-name>}"
  done <<< "$PUBLIC_INSTANCES"
fi

# ─── IGW Attachment ───────────────────────────────────────────
section "Internet Gateways"

IGWS=$(aws ec2 describe-internet-gateways \
  --query 'InternetGateways[*].[InternetGatewayId,Attachments[0].VpcId]' \
  --output text 2>/dev/null)

IGW_COUNT=$(echo "$IGWS" | grep -c "igw-" 2>/dev/null || echo 0)
info "$IGW_COUNT Internet Gateway(s) found"
while read -r IGW_ID VPC_ID; do
  info "  $IGW_ID → VPC $VPC_ID"
done <<< "$IGWS"

# ─── Default VPC ──────────────────────────────────────────────
section "Default VPC"

DEFAULT_VPC=$(aws ec2 describe-vpcs \
  --filters "Name=isDefault,Values=true" \
  --query 'Vpcs[*].VpcId' --output text 2>/dev/null)

if [[ -z "$DEFAULT_VPC" ]]; then
  pass "Default VPC has been deleted"
else
  warn "Default VPC exists: $DEFAULT_VPC — consider deleting if not used (attack surface)"
  # Check if there are any instances in the default VPC
  DEFAULT_INSTANCES=$(aws ec2 describe-instances \
    --filters "Name=vpc-id,Values=$DEFAULT_VPC" "Name=instance-state-name,Values=running" \
    --query 'Reservations[*].Instances[*].InstanceId' --output text 2>/dev/null)
  if [[ -n "$DEFAULT_INSTANCES" ]]; then
    fail "Running instances found in default VPC: $DEFAULT_INSTANCES"
  else
    pass "No running instances in default VPC"
  fi
fi

# ─── VPC Peering — Route Permissions ─────────────────────────
section "VPC Peering Connections"

PEERINGS=$(aws ec2 describe-vpc-peering-connections \
  --filters "Name=status-code,Values=active" \
  --query 'VpcPeeringConnections[*].[VpcPeeringConnectionId,RequesterVpcInfo.VpcId,AccepterVpcInfo.VpcId,RequesterVpcInfo.OwnerId]' \
  --output text 2>/dev/null)

if [[ -z "$PEERINGS" ]]; then
  pass "No active VPC peering connections"
else
  PEER_COUNT=$(echo "$PEERINGS" | wc -l | tr -d ' ')
  warn "$PEER_COUNT active VPC peering connection(s) — validate routing is least-privilege:"
  while read -r PEER_ID REQ_VPC ACC_VPC OWNER; do
    info "  $PEER_ID: $REQ_VPC ↔ $ACC_VPC (owner: $OWNER)"
  done <<< "$PEERINGS"
fi

# ─── VPC Endpoints ────────────────────────────────────────────
section "VPC Endpoints — Private Service Access"

VPCS_LIST=($VPCS)
VPC_ENDPOINT_RECOMMENDED=("com.amazonaws.${AWS_REGION}.s3" "com.amazonaws.${AWS_REGION}.dynamodb" \
  "com.amazonaws.${AWS_REGION}.secretsmanager" "com.amazonaws.${AWS_REGION}.ssm" \
  "com.amazonaws.${AWS_REGION}.ec2" "com.amazonaws.${AWS_REGION}.sts")

EXISTING_ENDPOINTS=$(aws ec2 describe-vpc-endpoints \
  --query 'VpcEndpoints[*].ServiceName' --output text 2>/dev/null)

for SVC in "${VPC_ENDPOINT_RECOMMENDED[@]}"; do
  if echo "$EXISTING_ENDPOINTS" | grep -q "$SVC"; then
    pass "VPC endpoint exists: $SVC"
  else
    warn "No VPC endpoint for $SVC — traffic routes over internet (if in VPC)"
  fi
done

# ─── NACLs — Default Allow-All ───────────────────────────────
section "Network ACLs"

DEFAULT_NACLS=$(aws ec2 describe-network-acls \
  --filters "Name=default,Values=true" \
  --query 'NetworkAcls[*].[NetworkAclId,VpcId]' --output text 2>/dev/null)

NACL_COUNT=$(echo "$DEFAULT_NACLS" | grep -c "acl-" 2>/dev/null || echo 0)
if [[ "$NACL_COUNT" -gt 0 ]]; then
  info "$NACL_COUNT default NACL(s) — default NACLs allow all traffic; customize for defense-in-depth"
  while read -r NACL_ID VPC_ID; do
    warn "Default NACL $NACL_ID on VPC $VPC_ID — no custom deny rules applied"
  done <<< "$DEFAULT_NACLS"
else
  pass "No default NACLs found"
fi

# ─── Summary ─────────────────────────────────────────────────
print_summary "Network Security"
write_json_summary "02-network"
