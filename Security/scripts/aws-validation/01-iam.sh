#!/usr/bin/env bash
# ============================================================
# 01-iam.sh — IAM Security Validation
# Checks: root account, users, access keys, MFA, password
#         policy, admin policies, privilege escalation surface
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

header "IAM Security Validation"
check_aws_access

# ─── Root Account ────────────────────────────────────────────
section "Root Account"

ROOT_KEYS=$(aws iam get-account-summary \
  --query 'SummaryMap.AccountAccessKeysPresent' --output text 2>/dev/null)
if [[ "$ROOT_KEYS" == "0" ]]; then
  pass "Root account has no access keys"
else
  fail "Root account has $ROOT_KEYS active access key(s) — DELETE IMMEDIATELY"
fi

ROOT_MFA=$(aws iam get-account-summary \
  --query 'SummaryMap.AccountMFAEnabled' --output text 2>/dev/null)
if [[ "$ROOT_MFA" == "1" ]]; then
  pass "Root account has MFA enabled"
else
  fail "Root account does NOT have MFA enabled"
fi

# ─── IAM Users ───────────────────────────────────────────────
section "IAM Users"

USERS=$(aws iam list-users --query 'Users[*].UserName' --output text 2>/dev/null)
USER_COUNT=$(aws iam get-account-summary \
  --query 'SummaryMap.Users' --output text 2>/dev/null)

if [[ "$USER_COUNT" == "0" ]]; then
  pass "No IAM users found (use IAM Identity Center / SSO instead)"
else
  warn "$USER_COUNT IAM user(s) found — prefer IAM Identity Center over long-lived IAM users"
  info "Users: $(echo "$USERS" | tr '\n' ', ')"
fi

# ─── IAM Users Without MFA ───────────────────────────────────
section "IAM Users — MFA Enforcement"

USERS_WITHOUT_MFA=()
if [[ -n "$USERS" ]]; then
  for USER in $USERS; do
    MFA_DEVICES=$(aws iam list-mfa-devices --user-name "$USER" \
      --query 'MFADevices[*].SerialNumber' --output text 2>/dev/null)
    if [[ -z "$MFA_DEVICES" ]]; then
      USERS_WITHOUT_MFA+=("$USER")
    fi
  done
fi

if [[ ${#USERS_WITHOUT_MFA[@]} -eq 0 ]]; then
  pass "All IAM users have MFA enabled"
else
  fail "IAM users WITHOUT MFA: ${USERS_WITHOUT_MFA[*]}"
fi

# ─── IAM Users Console Access Without MFA ────────────────────
section "IAM Users — Console Access & Password Age"

aws iam generate-credential-report > /dev/null 2>&1 || true
sleep 3
CRED_REPORT=$(aws iam get-credential-report \
  --query Content --output text 2>/dev/null | base64 --decode 2>/dev/null || echo "")

if [[ -n "$CRED_REPORT" ]]; then
  # Parse CSV: user,arn,user_creation_time,password_enabled,...
  USERS_WITH_OLD_PASSWORDS=()
  while IFS=',' read -r user arn created pw_enabled pw_last_used pw_last_changed pw_next_rotation \
    mfa_active ak1_active ak1_last_rotated ak1_last_used_date ak1_last_used_region ak1_last_used_svc \
    ak2_active ak2_last_rotated ak2_last_used_date ak2_last_used_region ak2_last_used_svc \
    cert1_active cert2_active; do
    [[ "$user" == "user" ]] && continue  # header
    [[ "$user" == "<root_account>" ]] && continue
    # Check for old access keys (> 90 days)
    for rotated in "$ak1_last_rotated" "$ak2_last_rotated"; do
      if [[ "$rotated" != "N/A" && -n "$rotated" ]]; then
        ROTATED_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%S+00:00" "$rotated" "+%s" 2>/dev/null || \
                        date -d "$rotated" "+%s" 2>/dev/null || echo "0")
        NOW_EPOCH=$(date "+%s")
        AGE_DAYS=$(( (NOW_EPOCH - ROTATED_EPOCH) / 86400 ))
        if [[ $AGE_DAYS -gt 90 ]]; then
          USERS_WITH_OLD_PASSWORDS+=("$user(${AGE_DAYS}d)")
        fi
      fi
    done
  done <<< "$CRED_REPORT"

  if [[ ${#USERS_WITH_OLD_PASSWORDS[@]} -eq 0 ]]; then
    pass "All access keys rotated within 90 days"
  else
    fail "Access keys older than 90 days: ${USERS_WITH_OLD_PASSWORDS[*]}"
  fi
else
  warn "Could not generate credential report — check permissions"
fi

# ─── Password Policy ─────────────────────────────────────────
section "IAM Account Password Policy"

PW_POLICY=$(aws iam get-account-password-policy 2>/dev/null || echo "none")
if [[ "$PW_POLICY" == "none" ]]; then
  fail "No IAM password policy configured"
else
  MIN_LEN=$(echo "$PW_POLICY" | python3 -c "import sys,json; d=json.load(sys.stdin); \
    print(d.get('PasswordPolicy',{}).get('MinimumPasswordLength',0))" 2>/dev/null || echo 0)
  UPPERCASE=$(echo "$PW_POLICY" | python3 -c "import sys,json; d=json.load(sys.stdin); \
    print(d.get('PasswordPolicy',{}).get('RequireUppercaseCharacters',False))" 2>/dev/null || echo False)
  SYMBOLS=$(echo "$PW_POLICY" | python3 -c "import sys,json; d=json.load(sys.stdin); \
    print(d.get('PasswordPolicy',{}).get('RequireSymbols',False))" 2>/dev/null || echo False)
  REUSE=$(echo "$PW_POLICY" | python3 -c "import sys,json; d=json.load(sys.stdin); \
    print(d.get('PasswordPolicy',{}).get('PasswordReusePrevention',0))" 2>/dev/null || echo 0)
  MAX_AGE=$(echo "$PW_POLICY" | python3 -c "import sys,json; d=json.load(sys.stdin); \
    print(d.get('PasswordPolicy',{}).get('MaxPasswordAge',0))" 2>/dev/null || echo 0)

  [[ "$MIN_LEN" -ge 14 ]] && pass "Password minimum length ≥ 14 ($MIN_LEN)" \
    || fail "Password minimum length < 14 (current: $MIN_LEN)"
  [[ "$UPPERCASE" == "True" ]] && pass "Password requires uppercase" \
    || fail "Password policy does not require uppercase"
  [[ "$SYMBOLS" == "True" ]] && pass "Password requires symbols" \
    || fail "Password policy does not require symbols"
  [[ "$REUSE" -ge 24 ]] && pass "Password reuse prevention ≥ 24 ($REUSE)" \
    || warn "Password reuse prevention is $REUSE (recommend ≥ 24)"
  [[ "$MAX_AGE" -gt 0 && "$MAX_AGE" -le 90 ]] && pass "Password max age ≤ 90 days ($MAX_AGE)" \
    || warn "Password max age is $MAX_AGE (recommend ≤ 90 days)"
fi

# ─── Admin Policies Attached Directly to Users ───────────────
section "Overprivileged IAM — Admin Policies on Users"

ADMIN_USERS=()
if [[ -n "$USERS" ]]; then
  for USER in $USERS; do
    POLICIES=$(aws iam list-attached-user-policies --user-name "$USER" \
      --query 'AttachedPolicies[*].PolicyArn' --output text 2>/dev/null)
    for ARN in $POLICIES; do
      if [[ "$ARN" == *"AdministratorAccess"* || "$ARN" == *"PowerUser"* ]]; then
        ADMIN_USERS+=("$USER → $ARN")
      fi
    done
    # Check inline policies with wildcard actions
    INLINE=$(aws iam list-user-policies --user-name "$USER" \
      --query 'PolicyNames' --output text 2>/dev/null)
    for PNAME in $INLINE; do
      DOC=$(aws iam get-user-policy --user-name "$USER" --policy-name "$PNAME" \
        --query 'PolicyDocument' --output text 2>/dev/null | python3 -c \
        "import sys,json,urllib.parse; print(json.dumps(json.loads(urllib.parse.unquote(sys.stdin.read()))))" 2>/dev/null || echo "")
      if echo "$DOC" | grep -q '"Action": "\*"'; then
        ADMIN_USERS+=("$USER (inline policy $PNAME has Action:*)")
      fi
    done
  done
fi

if [[ ${#ADMIN_USERS[@]} -eq 0 ]]; then
  pass "No IAM users have AdministratorAccess or wildcard inline policies"
else
  fail "Admin/wildcard policies found on users: ${ADMIN_USERS[*]}"
fi

# ─── Roles With Wildcard Resource/Action ─────────────────────
section "IAM Roles — Wildcard Permissions"

ROLES=$(aws iam list-roles --query 'Roles[*].RoleName' --output text 2>/dev/null)
WILD_ROLES=()
for ROLE in $ROLES; do
  # Check attached managed policies
  ATTACHED=$(aws iam list-attached-role-policies --role-name "$ROLE" \
    --query 'AttachedPolicies[*].PolicyArn' --output text 2>/dev/null)
  for ARN in $ATTACHED; do
    if [[ "$ARN" == *"AdministratorAccess"* ]]; then
      WILD_ROLES+=("$ROLE → AdministratorAccess")
    fi
  done
  # Check inline policies
  INLINE_NAMES=$(aws iam list-role-policies --role-name "$ROLE" \
    --query 'PolicyNames' --output text 2>/dev/null)
  for PNAME in $INLINE_NAMES; do
    DOC=$(aws iam get-role-policy --role-name "$ROLE" --policy-name "$PNAME" \
      --query 'PolicyDocument' --output text 2>/dev/null || echo "")
    if echo "$DOC" | grep -qE '"Action"[[:space:]]*:[[:space:]]*"\*"'; then
      WILD_ROLES+=("$ROLE (inline $PNAME: Action:*)")
    fi
  done
done

if [[ ${#WILD_ROLES[@]} -eq 0 ]]; then
  pass "No roles found with AdministratorAccess or Action:* inline policies"
else
  warn "${#WILD_ROLES[@]} role(s) with broad permissions (review if intentional):"
  for R in "${WILD_ROLES[@]}"; do info "  $R"; done
fi

# ─── Privilege Escalation Surface ────────────────────────────
section "IAM Privilege Escalation — High-Risk Permissions"

PRIVESC_ACTIONS=(
  "iam:CreateUser"
  "iam:AttachUserPolicy"
  "iam:AttachRolePolicy"
  "iam:PutRolePolicy"
  "iam:PutUserPolicy"
  "iam:CreateAccessKey"
  "iam:UpdateAssumeRolePolicy"
  "iam:PassRole"
)

info "High-risk actions that enable privilege escalation (manual review needed):"
info "Check that these are only granted to trusted roles with strong justification:"
for ACTION in "${PRIVESC_ACTIONS[@]}"; do
  info "  • $ACTION"
done
warn "Run 'principalmapper' or 'enumerate-iam' to map escalation paths in this account"

# ─── Access Analyzer ─────────────────────────────────────────
section "IAM Access Analyzer"

ANALYZERS=$(aws accessanalyzer list-analyzers \
  --query 'analyzers[?status==`ACTIVE`].name' --output text 2>/dev/null || echo "")
if [[ -n "$ANALYZERS" && "$ANALYZERS" != "None" ]]; then
  pass "IAM Access Analyzer active: $ANALYZERS"
  FINDINGS=$(aws accessanalyzer list-findings \
    --analyzer-arn "$(aws accessanalyzer list-analyzers \
      --query 'analyzers[0].arn' --output text 2>/dev/null)" \
    --filter '{"status":{"eq":["ACTIVE"]}}' \
    --query 'findings | length(@)' --output text 2>/dev/null || echo "0")
  if [[ "$FINDINGS" == "0" ]]; then
    pass "Access Analyzer: no active findings"
  else
    fail "Access Analyzer: $FINDINGS active finding(s) — resources shared outside org"
  fi
else
  fail "IAM Access Analyzer not enabled — cannot detect external resource sharing"
fi

# ─── Summary ─────────────────────────────────────────────────
print_summary "IAM Security"
write_json_summary "01-iam"
