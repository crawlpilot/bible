#!/usr/bin/env bash
# Shared functions, colors, and counters — sourced by every validation script

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0
INFO_COUNT=0

SCRIPT_RESULTS=()   # array of "PASS|FAIL|WARN:message" for summary

pass() {
  echo -e "  ${GREEN}[PASS]${NC} $1"
  ((PASS_COUNT++))
  SCRIPT_RESULTS+=("PASS:$1")
}

fail() {
  echo -e "  ${RED}[FAIL]${NC} $1"
  ((FAIL_COUNT++))
  SCRIPT_RESULTS+=("FAIL:$1")
}

warn() {
  echo -e "  ${YELLOW}[WARN]${NC} $1"
  ((WARN_COUNT++))
  SCRIPT_RESULTS+=("WARN:$1")
}

info() {
  echo -e "  ${CYAN}[INFO]${NC} $1"
}

section() {
  echo -e "\n${BOLD}${BLUE}━━━ $1 ━━━${NC}"
}

header() {
  local title="$1"
  local width=60
  echo -e "\n${BOLD}${BLUE}"
  printf '%.0s═' $(seq 1 $width); echo
  printf "  %-$((width-4))s  \n" "$title"
  printf '%.0s═' $(seq 1 $width); echo
  echo -e "${NC}"
}

print_summary() {
  local script_name="${1:-Validation}"
  echo -e "\n${BOLD}${BLUE}━━━ Summary: $script_name ━━━${NC}"
  echo -e "  ${GREEN}PASS : $PASS_COUNT${NC}"
  echo -e "  ${RED}FAIL : $FAIL_COUNT${NC}"
  echo -e "  ${YELLOW}WARN : $WARN_COUNT${NC}"
  echo ""
  if [[ $FAIL_COUNT -gt 0 ]]; then
    echo -e "  ${RED}${BOLD}Failing checks:${NC}"
    for r in "${SCRIPT_RESULTS[@]}"; do
      if [[ $r == FAIL:* ]]; then
        echo -e "  ${RED}  ✗${NC} ${r#FAIL:}"
      fi
    done
  fi
  if [[ $WARN_COUNT -gt 0 ]]; then
    echo -e "\n  ${YELLOW}${BOLD}Warnings:${NC}"
    for r in "${SCRIPT_RESULTS[@]}"; do
      if [[ $r == WARN:* ]]; then
        echo -e "  ${YELLOW}  ⚠${NC} ${r#WARN:}"
      fi
    done
  fi
  echo ""
}

# Write results to a JSON summary file for the master runner
write_json_summary() {
  local script_name="$1"
  local output_dir="${RESULTS_DIR:-/tmp/aws-validation-results}"
  mkdir -p "$output_dir"
  local file="$output_dir/${script_name}.json"
  cat > "$file" <<EOF
{
  "script": "$script_name",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "account": "${ACCOUNT_ID:-unknown}",
  "region": "${AWS_REGION:-unknown}",
  "pass": $PASS_COUNT,
  "fail": $FAIL_COUNT,
  "warn": $WARN_COUNT
}
EOF
  echo -e "  ${CYAN}Results saved → $file${NC}"
}

# Safely run an AWS CLI command; return empty string on error
aws_safe() {
  aws "$@" 2>/dev/null || echo ""
}

# Check if AWS CLI is configured and reachable
check_aws_access() {
  ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
  if [[ -z "$ACCOUNT_ID" ]]; then
    echo -e "${RED}[ERROR]${NC} Cannot reach AWS. Check credentials / profile / region."
    exit 1
  fi
  CALLER_ARN=$(aws sts get-caller-identity --query Arn --output text 2>/dev/null)
  AWS_REGION="${AWS_DEFAULT_REGION:-$(aws configure get region 2>/dev/null || echo us-east-1)}"
  echo -e "  ${GREEN}Account :${NC} $ACCOUNT_ID"
  echo -e "  ${GREEN}Identity:${NC} $CALLER_ARN"
  echo -e "  ${GREEN}Region  :${NC} $AWS_REGION"
}

# Dangerous port list for SG checks
DANGEROUS_PORTS=(22 3389 3306 5432 1433 27017 6379 9200 9300 2181 2375 2376)

is_dangerous_port() {
  local port=$1
  for p in "${DANGEROUS_PORTS[@]}"; do
    [[ "$port" == "$p" ]] && return 0
  done
  return 1
}
