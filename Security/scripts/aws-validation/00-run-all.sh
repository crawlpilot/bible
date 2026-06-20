#!/usr/bin/env bash
# ============================================================
# 00-run-all.sh — Master AWS Security Validation Runner
#
# Compatible with bash 3.2+ (macOS default shell)
# Results are read from per-script JSON files — no associative arrays.
#
# Usage:
#   ./00-run-all.sh                     # run all scripts
#   ./00-run-all.sh --only 01 03 07     # run specific scripts by number
#   ./00-run-all.sh --skip 05           # skip specific scripts by number
#   ./00-run-all.sh --output /tmp/audit # custom output directory
# ============================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
OUTPUT_DIR="${SCRIPT_DIR}/results/${TIMESTAMP}"
export RESULTS_DIR="$OUTPUT_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

ONLY_FILTER=""   # comma-separated numbers, e.g. "01,03,07"
SKIP_FILTER=""   # comma-separated numbers, e.g. "05"

# ─── Argument Parsing ─────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --only)
      shift
      while [[ $# -gt 0 && "$1" != --* ]]; do
        ONLY_FILTER="${ONLY_FILTER:+$ONLY_FILTER,}$1"
        shift
      done
      ;;
    --skip)
      shift
      while [[ $# -gt 0 && "$1" != --* ]]; do
        SKIP_FILTER="${SKIP_FILTER:+$SKIP_FILTER,}$1"
        shift
      done
      ;;
    --output)
      shift
      OUTPUT_DIR="$1"
      export RESULTS_DIR="$OUTPUT_DIR"
      shift
      ;;
    *) shift ;;
  esac
done

mkdir -p "$OUTPUT_DIR"
LOG_FILE="$OUTPUT_DIR/full-output.log"

# Script registry — "filename:label"
ALL_SCRIPTS="
01-iam.sh:IAM Security
02-network.sh:Network Security
03-s3.sh:S3 Security
04-rds.sh:RDS Security
05-compute.sh:Compute Security
06-secrets.sh:Secrets and Data
07-logging.sh:Logging and Detection
08-ssrf-imds.sh:SSRF and IMDS
"

# ─── Banner ───────────────────────────────────────────────────
echo -e "${BOLD}${BLUE}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║        AWS Security Validation Suite                    ║"
echo "║        Principal Engineer Security Review               ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "  ${CYAN}Output directory :${NC} $OUTPUT_DIR"
echo -e "  ${CYAN}Log file         :${NC} $LOG_FILE"
echo -e "  ${CYAN}Timestamp        :${NC} $TIMESTAMP"
echo ""

# ─── Verify AWS Access ────────────────────────────────────────
echo -e "${BOLD}Verifying AWS credentials...${NC}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
if [[ -z "$ACCOUNT_ID" ]]; then
  echo -e "${RED}[ERROR]${NC} Cannot reach AWS. Set AWS_PROFILE or configure credentials."
  exit 1
fi
export ACCOUNT_ID
CALLER_ARN=$(aws sts get-caller-identity --query Arn --output text 2>/dev/null || echo "unknown")
AWS_REGION="${AWS_DEFAULT_REGION:-$(aws configure get region 2>/dev/null || echo us-east-1)}"
export AWS_REGION

echo -e "  ${GREEN}Account :${NC} $ACCOUNT_ID"
echo -e "  ${GREEN}Identity:${NC} $CALLER_ARN"
echo -e "  ${GREEN}Region  :${NC} $AWS_REGION"
echo ""

# ─── Helper: read a field from a script's JSON result ─────────
# Usage: json_field <json_file> <field>   returns 0 if missing
json_field() {
  local file="$1" field="$2"
  if [[ -f "$file" ]]; then
    python3 -c "import json; d=json.load(open('$file')); print(d.get('$field', 0))" 2>/dev/null || echo 0
  else
    echo 0
  fi
}

# ─── Helper: should this script run? ─────────────────────────
should_run() {
  local script_file="$1"         # e.g. "03-s3.sh"
  local num="${script_file%%-*}" # e.g. "03"

  # --only filter: run only if num is in the list
  if [[ -n "$ONLY_FILTER" ]]; then
    echo "$ONLY_FILTER" | tr ',' '\n' | grep -qx "$num" || return 1
  fi

  # --skip filter: skip if num is in the list
  if [[ -n "$SKIP_FILTER" ]]; then
    echo "$SKIP_FILTER" | tr ',' '\n' | grep -qx "$num" && return 1
  fi

  return 0
}

# ─── Run Scripts ──────────────────────────────────────────────
# We store per-script outcome in plain files under $OUTPUT_DIR/meta/
META_DIR="$OUTPUT_DIR/meta"
mkdir -p "$META_DIR"

START_TIME=$(date +%s)

while IFS=: read -r SCRIPT_FILE SCRIPT_LABEL; do
  # Skip blank lines from the heredoc
  [[ -z "$SCRIPT_FILE" ]] && continue
  # Trim whitespace
  SCRIPT_FILE="${SCRIPT_FILE#"${SCRIPT_FILE%%[![:space:]]*}"}"
  SCRIPT_LABEL="${SCRIPT_LABEL#"${SCRIPT_LABEL%%[![:space:]]*}"}"
  [[ -z "$SCRIPT_FILE" ]] && continue

  # Apply filters
  if ! should_run "$SCRIPT_FILE"; then
    echo -e "  ${YELLOW}[SKIP]${NC} $SCRIPT_LABEL"
    continue
  fi

  FULL_SCRIPT="$SCRIPT_DIR/$SCRIPT_FILE"
  if [[ ! -f "$FULL_SCRIPT" ]]; then
    echo -e "  ${RED}[MISSING]${NC} $FULL_SCRIPT not found — skipping"
    echo "ERROR" > "$META_DIR/${SCRIPT_FILE}.status"
    continue
  fi

  echo -e "\n${BOLD}${BLUE}▶  $SCRIPT_LABEL${NC}  (${SCRIPT_FILE})"
  echo ""

  chmod +x "$FULL_SCRIPT"
  SCRIPT_START=$(date +%s)

  # Run; tee output to both terminal and log
  if bash "$FULL_SCRIPT" 2>&1 | tee -a "$LOG_FILE"; then
    echo "OK" > "$META_DIR/${SCRIPT_FILE}.status"
  else
    echo "FAILED" > "$META_DIR/${SCRIPT_FILE}.status"
  fi

  SCRIPT_END=$(date +%s)
  echo -e "  ${CYAN}Elapsed:${NC} $(( SCRIPT_END - SCRIPT_START ))s"

done <<EOF
$ALL_SCRIPTS
EOF

END_TIME=$(date +%s)
TOTAL_ELAPSED=$(( END_TIME - START_TIME ))

# ─── Consolidated Summary ─────────────────────────────────────
echo -e "\n${BOLD}${BLUE}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║                  FINAL SUMMARY                          ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "  Account  : $ACCOUNT_ID"
echo -e "  Region   : $AWS_REGION"
echo -e "  Duration : ${TOTAL_ELAPSED}s"
echo ""
printf "  ${BOLD}%-36s %5s %5s %5s  %-10s${NC}\n" "Domain" "PASS" "FAIL" "WARN" "Status"
printf "  %s\n" "$(printf '%.0s─' {1..66})"

TOTAL_PASS=0
TOTAL_FAIL=0
TOTAL_WARN=0
HTML_ROWS=""

while IFS=: read -r SCRIPT_FILE SCRIPT_LABEL; do
  [[ -z "$SCRIPT_FILE" ]] && continue
  SCRIPT_FILE="${SCRIPT_FILE#"${SCRIPT_FILE%%[![:space:]]*}"}"
  SCRIPT_LABEL="${SCRIPT_LABEL#"${SCRIPT_LABEL%%[![:space:]]*}"}"
  [[ -z "$SCRIPT_FILE" ]] && continue

  # Skip scripts that were not run
  [[ ! -f "$META_DIR/${SCRIPT_FILE}.status" ]] && continue

  STATUS=$(cat "$META_DIR/${SCRIPT_FILE}.status" 2>/dev/null || echo "NOT RUN")

  # Read counts from JSON result file written by the script
  JSON_FILE="${RESULTS_DIR}/${SCRIPT_FILE%.sh}.json"
  P=$(json_field "$JSON_FILE" pass)
  F=$(json_field "$JSON_FILE" fail)
  W=$(json_field "$JSON_FILE" warn)

  TOTAL_PASS=$(( TOTAL_PASS + P ))
  TOTAL_FAIL=$(( TOTAL_FAIL + F ))
  TOTAL_WARN=$(( TOTAL_WARN + W ))

  if [[ "$F" -gt 0 ]]; then
    STATUS_LABEL="${RED}ISSUES${NC}"
    HTML_STATUS='<span style="color:#c62828;font-weight:bold">ISSUES</span>'
  elif [[ "$W" -gt 0 ]]; then
    STATUS_LABEL="${YELLOW}WARNINGS${NC}"
    HTML_STATUS='<span style="color:#e65100;font-weight:bold">WARNINGS</span>'
  else
    STATUS_LABEL="${GREEN}CLEAN${NC}"
    HTML_STATUS='<span style="color:#2e7d32;font-weight:bold">CLEAN</span>'
  fi

  printf "  %-36s ${GREEN}%5s${NC} ${RED}%5s${NC} ${YELLOW}%5s${NC}  ${STATUS_LABEL}\n" \
    "$SCRIPT_LABEL" "$P" "$F" "$W"

  HTML_ROWS="${HTML_ROWS}<tr><td>${SCRIPT_LABEL}</td><td style='color:#2e7d32'>${P}</td><td style='color:#c62828'>${F}</td><td style='color:#e65100'>${W}</td><td>${HTML_STATUS}</td></tr>"$'\n'

done <<EOF
$ALL_SCRIPTS
EOF

printf "  %s\n" "$(printf '%.0s─' {1..66})"
printf "  ${BOLD}%-36s ${GREEN}%5s${NC} ${RED}%5s${NC} ${YELLOW}%5s${NC}${NC}\n" \
  "TOTAL" "$TOTAL_PASS" "$TOTAL_FAIL" "$TOTAL_WARN"
echo ""

# Overall risk rating
if [[ $TOTAL_FAIL -eq 0 && $TOTAL_WARN -eq 0 ]]; then
  RISK_LABEL="LOW — Account meets security baseline"
  RISK_COLOR="$GREEN"
  HTML_RISK='<span style="background:#e8f5e9;color:#2e7d32;padding:6px 14px;border-radius:4px;font-weight:bold">LOW — Account meets security baseline</span>'
elif [[ $TOTAL_FAIL -eq 0 ]]; then
  RISK_LABEL="MEDIUM — Warnings present, no critical failures"
  RISK_COLOR="$YELLOW"
  HTML_RISK='<span style="background:#fff3e0;color:#e65100;padding:6px 14px;border-radius:4px;font-weight:bold">MEDIUM — Warnings present, no critical failures</span>'
elif [[ $TOTAL_FAIL -le 5 ]]; then
  RISK_LABEL="HIGH — $TOTAL_FAIL issue(s) require attention"
  RISK_COLOR="$YELLOW"
  HTML_RISK='<span style="background:#ffebee;color:#c62828;padding:6px 14px;border-radius:4px;font-weight:bold">HIGH — '"$TOTAL_FAIL"' issue(s) require attention</span>'
else
  RISK_LABEL="CRITICAL — $TOTAL_FAIL security failures found"
  RISK_COLOR="$RED"
  HTML_RISK='<span style="background:#b71c1c;color:white;padding:6px 14px;border-radius:4px;font-weight:bold">CRITICAL — '"$TOTAL_FAIL"' security failures found</span>'
fi

echo -e "  ${BOLD}${RISK_COLOR}Overall Risk: $RISK_LABEL${NC}"
echo ""

# ─── HTML Report ──────────────────────────────────────────────
HTML_REPORT="$OUTPUT_DIR/report.html"
LOG_CONTENT=$(cat "$LOG_FILE" 2>/dev/null | \
  sed 's/\x1b\[[0-9;]*m//g' | \
  sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')

cat > "$HTML_REPORT" <<HTMLEOF
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>AWS Security Validation — $ACCOUNT_ID — $TIMESTAMP</title>
<style>
  body{font-family:'Segoe UI',Arial,sans-serif;max-width:1100px;margin:40px auto;padding:0 20px;background:#f5f5f5;color:#212121}
  h1{color:#1a237e;border-bottom:3px solid #1a237e;padding-bottom:10px}
  h2{color:#283593;margin-top:30px}
  .meta{background:#e8eaf6;padding:15px 20px;border-radius:8px;margin-bottom:30px;line-height:2}
  table{width:100%;border-collapse:collapse;background:white;border-radius:8px;overflow:hidden;box-shadow:0 2px 8px rgba(0,0,0,.1);margin-bottom:30px}
  th{background:#1a237e;color:white;padding:12px 16px;text-align:left}
  td{padding:10px 16px;border-bottom:1px solid #e0e0e0}
  tr:last-child td{border-bottom:none}
  tr:hover td{background:#f5f5f5}
  tfoot td{font-weight:bold;background:#eeeeee;border-top:2px solid #bdbdbd}
  .log{background:#1e1e1e;color:#d4d4d4;padding:20px;border-radius:8px;font-family:'Courier New',monospace;font-size:12px;white-space:pre-wrap;overflow:auto;max-height:700px}
</style>
</head>
<body>
<h1>🔐 AWS Security Validation Report</h1>
<div class="meta">
  <strong>Account:</strong> $ACCOUNT_ID &nbsp;|&nbsp;
  <strong>Region:</strong> $AWS_REGION &nbsp;|&nbsp;
  <strong>Identity:</strong> $CALLER_ARN<br>
  <strong>Timestamp:</strong> $TIMESTAMP &nbsp;|&nbsp;
  <strong>Duration:</strong> ${TOTAL_ELAPSED}s
</div>

<h2>Overall Risk</h2>
<p>${HTML_RISK}</p>

<h2>Results by Domain</h2>
<table>
<thead><tr><th>Domain</th><th>Pass ✓</th><th>Fail ✗</th><th>Warn ⚠</th><th>Status</th></tr></thead>
<tbody>
${HTML_ROWS}
</tbody>
<tfoot><tr><td>TOTAL</td><td style="color:#2e7d32">$TOTAL_PASS</td><td style="color:#c62828">$TOTAL_FAIL</td><td style="color:#e65100">$TOTAL_WARN</td><td></td></tr></tfoot>
</table>

<h2>Full Output Log</h2>
<div class="log">${LOG_CONTENT}</div>
</body>
</html>
HTMLEOF

echo -e "  ${GREEN}Reports written:${NC}"
echo -e "    HTML  → $HTML_REPORT"
echo -e "    Log   → $LOG_FILE"
echo -e "    JSON  → $OUTPUT_DIR/*.json"
echo ""

[[ $TOTAL_FAIL -gt 0 ]] && exit 1 || exit 0
