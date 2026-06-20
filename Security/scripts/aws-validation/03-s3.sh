#!/usr/bin/env bash
# ============================================================
# 03-s3.sh — S3 Security Validation
# Checks: public access block, bucket policies, ACLs,
#         encryption, versioning, logging, object lock
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

header "S3 Security Validation"
check_aws_access

# ─── Account-Level Public Access Block ───────────────────────
section "S3 Account-Level Public Access Block"

ACCT_BLOCK=$(aws s3control get-public-access-block \
  --account-id "$ACCOUNT_ID" 2>/dev/null || echo "none")

if [[ "$ACCT_BLOCK" == "none" ]]; then
  fail "Account-level S3 Public Access Block is NOT configured"
else
  BLOCK_PA=$(echo "$ACCT_BLOCK" | python3 -c "import sys,json; d=json.load(sys.stdin); \
    c=d.get('PublicAccessBlockConfiguration',{}); \
    print(all([c.get('BlockPublicAcls',False), c.get('IgnorePublicAcls',False), \
    c.get('BlockPublicPolicy',False), c.get('RestrictPublicBuckets',False)]))" 2>/dev/null || echo False)
  if [[ "$BLOCK_PA" == "True" ]]; then
    pass "Account-level S3 Public Access Block: all 4 settings enabled"
  else
    fail "Account-level S3 Public Access Block: not all settings enabled"
    echo "$ACCT_BLOCK" | python3 -c "import sys,json; d=json.load(sys.stdin); \
      c=d.get('PublicAccessBlockConfiguration',{}); \
      [print(f'    {k}: {v}') for k,v in c.items()]" 2>/dev/null || true
  fi
fi

# ─── Per-Bucket Checks ────────────────────────────────────────
section "Per-Bucket Security Checks"

BUCKETS=$(aws s3api list-buckets --query 'Buckets[*].Name' --output text 2>/dev/null)
BUCKET_COUNT=$(echo "$BUCKETS" | wc -w | tr -d ' ')
info "Checking $BUCKET_COUNT bucket(s)..."

PUBLIC_BUCKETS=()
UNENCRYPTED_BUCKETS=()
NO_VERSIONING_BUCKETS=()
NO_LOGGING_BUCKETS=()
HTTP_ALLOWED_BUCKETS=()
NO_BLOCK_BUCKETS=()

for BUCKET in $BUCKETS; do
  echo -e "  ${CYAN}Bucket:${NC} $BUCKET"

  # 1. Public Access Block per bucket
  BUCKET_BLOCK=$(aws s3api get-public-access-block --bucket "$BUCKET" 2>/dev/null || echo "none")
  if [[ "$BUCKET_BLOCK" == "none" ]]; then
    NO_BLOCK_BUCKETS+=("$BUCKET")
    echo -e "    ${RED}[FAIL]${NC} Public Access Block: NOT configured on bucket"
  else
    ALL_BLOCKED=$(echo "$BUCKET_BLOCK" | python3 -c "import sys,json; \
      d=json.load(sys.stdin).get('PublicAccessBlockConfiguration',{}); \
      print(all([d.get('BlockPublicAcls',False),d.get('IgnorePublicAcls',False), \
      d.get('BlockPublicPolicy',False),d.get('RestrictPublicBuckets',False)]))" 2>/dev/null || echo False)
    if [[ "$ALL_BLOCKED" == "True" ]]; then
      echo -e "    ${GREEN}[PASS]${NC} Public Access Block: all 4 settings enabled"
    else
      NO_BLOCK_BUCKETS+=("$BUCKET")
      echo -e "    ${RED}[FAIL]${NC} Public Access Block: not fully enabled"
    fi
  fi

  # 2. Bucket ACL — public?
  ACL=$(aws s3api get-bucket-acl --bucket "$BUCKET" \
    --query 'Grants[*].Grantee.URI' --output text 2>/dev/null || echo "")
  if echo "$ACL" | grep -q "AllUsers\|AuthenticatedUsers"; then
    PUBLIC_BUCKETS+=("$BUCKET")
    echo -e "    ${RED}[FAIL]${NC} ACL grants public access (AllUsers or AuthenticatedUsers)"
  else
    echo -e "    ${GREEN}[PASS]${NC} ACL: no public grants"
  fi

  # 3. Bucket Policy — allows Principal:*?
  POLICY=$(aws s3api get-bucket-policy --bucket "$BUCKET" \
    --query 'Policy' --output text 2>/dev/null || echo "")
  if [[ -n "$POLICY" && "$POLICY" != "None" ]]; then
    PUBLIC_POLICY=$(echo "$POLICY" | python3 -c "
import sys, json, urllib.parse
try:
    p = json.loads(sys.stdin.read())
    for s in p.get('Statement', []):
        principal = s.get('Principal', '')
        effect = s.get('Effect', '')
        if effect == 'Allow' and (principal == '*' or principal == {'AWS': '*'}):
            print('PUBLIC')
            break
except: pass
" 2>/dev/null || echo "")
    if [[ "$PUBLIC_POLICY" == "PUBLIC" ]]; then
      PUBLIC_BUCKETS+=("$BUCKET(policy)")
      echo -e "    ${RED}[FAIL]${NC} Bucket policy grants public access (Principal: *)"
    else
      echo -e "    ${GREEN}[PASS]${NC} Bucket policy: no public Principal"
    fi

    # 4. HTTPS-only policy check
    HTTPS_ONLY=$(echo "$POLICY" | python3 -c "
import sys, json
try:
    p = json.loads(sys.stdin.read())
    for s in p.get('Statement', []):
        cond = s.get('Condition', {})
        if (s.get('Effect') == 'Deny' and
            cond.get('Bool', {}).get('aws:SecureTransport') in ('false', False)):
            print('OK')
            break
except: pass
" 2>/dev/null || echo "")
    if [[ "$HTTPS_ONLY" == "OK" ]]; then
      echo -e "    ${GREEN}[PASS]${NC} HTTPS-only policy (denies HTTP)"
    else
      HTTP_ALLOWED_BUCKETS+=("$BUCKET")
      echo -e "    ${YELLOW}[WARN]${NC} No policy enforcing HTTPS-only access"
    fi
  else
    warn "    No bucket policy set on $BUCKET"
    HTTP_ALLOWED_BUCKETS+=("$BUCKET")
  fi

  # 5. Encryption
  ENC=$(aws s3api get-bucket-encryption --bucket "$BUCKET" 2>/dev/null || echo "none")
  if [[ "$ENC" == "none" ]]; then
    UNENCRYPTED_BUCKETS+=("$BUCKET")
    echo -e "    ${RED}[FAIL]${NC} Server-side encryption: NOT enabled"
  else
    ENC_TYPE=$(echo "$ENC" | python3 -c "import sys,json; \
      r=json.load(sys.stdin).get('ServerSideEncryptionConfiguration',{}).get('Rules',[{}]); \
      print(r[0].get('ApplyServerSideEncryptionByDefault',{}).get('SSEAlgorithm','unknown'))" 2>/dev/null || echo unknown)
    echo -e "    ${GREEN}[PASS]${NC} Server-side encryption: $ENC_TYPE"
  fi

  # 6. Versioning
  VERSIONING=$(aws s3api get-bucket-versioning --bucket "$BUCKET" \
    --query 'Status' --output text 2>/dev/null || echo "")
  if [[ "$VERSIONING" == "Enabled" ]]; then
    echo -e "    ${GREEN}[PASS]${NC} Versioning: Enabled"
  elif [[ "$VERSIONING" == "Suspended" ]]; then
    NO_VERSIONING_BUCKETS+=("$BUCKET")
    echo -e "    ${YELLOW}[WARN]${NC} Versioning: Suspended"
  else
    NO_VERSIONING_BUCKETS+=("$BUCKET")
    echo -e "    ${YELLOW}[WARN]${NC} Versioning: Not enabled"
  fi

  # 7. Access logging
  LOGGING=$(aws s3api get-bucket-logging --bucket "$BUCKET" \
    --query 'LoggingEnabled' --output text 2>/dev/null || echo "")
  if [[ -n "$LOGGING" && "$LOGGING" != "None" ]]; then
    echo -e "    ${GREEN}[PASS]${NC} Access logging: enabled"
  else
    NO_LOGGING_BUCKETS+=("$BUCKET")
    echo -e "    ${YELLOW}[WARN]${NC} Access logging: NOT enabled"
  fi

  echo ""
done

# ─── Consolidated Failures ────────────────────────────────────
section "S3 Summary of Issues"

[[ ${#PUBLIC_BUCKETS[@]} -eq 0 ]] \
  && pass "No publicly accessible buckets found" \
  || fail "Public buckets: ${PUBLIC_BUCKETS[*]}"

[[ ${#UNENCRYPTED_BUCKETS[@]} -eq 0 ]] \
  && pass "All buckets have server-side encryption" \
  || fail "Unencrypted buckets: ${UNENCRYPTED_BUCKETS[*]}"

[[ ${#NO_BLOCK_BUCKETS[@]} -eq 0 ]] \
  && pass "All buckets have Public Access Block configured" \
  || fail "Buckets without full Public Access Block: ${NO_BLOCK_BUCKETS[*]}"

[[ ${#HTTP_ALLOWED_BUCKETS[@]} -eq 0 ]] \
  && pass "All buckets enforce HTTPS-only" \
  || warn "Buckets that may allow HTTP (no deny aws:SecureTransport=false): ${HTTP_ALLOWED_BUCKETS[*]}"

[[ ${#NO_VERSIONING_BUCKETS[@]} -eq 0 ]] \
  && pass "All buckets have versioning enabled" \
  || warn "Buckets without versioning: ${NO_VERSIONING_BUCKETS[*]}"

[[ ${#NO_LOGGING_BUCKETS[@]} -eq 0 ]] \
  && pass "All buckets have access logging enabled" \
  || warn "Buckets without access logging: ${NO_LOGGING_BUCKETS[*]}"

# ─── S3 Macie ─────────────────────────────────────────────────
section "Amazon Macie"

MACIE=$(aws macie2 get-macie-session \
  --query 'status' --output text 2>/dev/null || echo "DISABLED")
if [[ "$MACIE" == "ENABLED" ]]; then
  pass "Amazon Macie is ENABLED (ML-based PII detection in S3)"
else
  warn "Amazon Macie is not enabled — no automated PII discovery in S3"
fi

# ─── Summary ─────────────────────────────────────────────────
print_summary "S3 Security"
write_json_summary "03-s3"
