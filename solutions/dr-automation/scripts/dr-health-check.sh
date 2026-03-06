#!/usr/bin/env bash
##############################################################################
# DR Health Check Script
# Runs on a cron schedule (every RPO minutes) to validate primary availability.
# If primary is unreachable for threshold checks, triggers GitHub Actions DR pipeline.
##############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATUS_FILE="${SCRIPT_DIR}/dr-status.json"
FAILURE_COUNTER_FILE="/tmp/dr-failure-count"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
MAX_FAILURES="${MAX_CONSECUTIVE_FAILURES:-3}"

log() { echo "[${TIMESTAMP}] $*"; }

# Read config from status file
PRIMARY_REGION=$(jq -r '.primary_region // "us-south"' "${STATUS_FILE}" 2>/dev/null || echo "us-south")
CURRENT_STATUS=$(jq -r '.status // "standby"' "${STATUS_FILE}" 2>/dev/null || echo "standby")

log "Health check running. Current DR status: ${CURRENT_STATUS}"

if [[ "${CURRENT_STATUS}" == "active" ]]; then
  log "DR is already active. Skipping primary health check."
  exit 0
fi

##############################################################################
# Check primary region reachability via IBM Cloud API
##############################################################################
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  "https://${PRIMARY_REGION}.iaas.cloud.ibm.com/v1/regions/${PRIMARY_REGION}?version=2024-01-15" \
  -H "Authorization: Bearer $(ibmcloud iam oauth-tokens --output json | jq -r '.iam_token')" \
  --max-time 10 2>/dev/null || echo "000")

if [[ "${HTTP_CODE}" == "200" ]]; then
  log "Primary region ${PRIMARY_REGION} is reachable (HTTP ${HTTP_CODE}). Resetting failure counter."
  echo "0" > "${FAILURE_COUNTER_FILE}"
  exit 0
fi

##############################################################################
# Primary unreachable - increment failure counter
##############################################################################
CURRENT_FAILURES=$(cat "${FAILURE_COUNTER_FILE}" 2>/dev/null || echo "0")
NEW_FAILURES=$((CURRENT_FAILURES + 1))
echo "${NEW_FAILURES}" > "${FAILURE_COUNTER_FILE}"

log "WARN: Primary region ${PRIMARY_REGION} unreachable (HTTP ${HTTP_CODE}). Consecutive failures: ${NEW_FAILURES}/${MAX_FAILURES}"

if [[ "${NEW_FAILURES}" -ge "${MAX_FAILURES}" ]]; then
  log "ALERT: Failure threshold reached. Triggering DR pipeline via GitHub Actions..."

  # Trigger GitHub Actions workflow_dispatch for DR failover
  if [[ -n "${GITHUB_TOKEN:-}" && -n "${GITHUB_REPO:-}" ]]; then
    curl -s -X POST \
      "https://api.github.com/repos/${GITHUB_REPO}/actions/workflows/dr-failover.yml/dispatches" \
      -H "Authorization: Bearer ${GITHUB_TOKEN}" \
      -H "Accept: application/vnd.github+json" \
      -d "{\"ref\": \"main\", \"inputs\": {\"trigger\": \"auto-health-check\", \"timestamp\": \"${TIMESTAMP}\"}}"
    log "GitHub Actions DR pipeline triggered for repo: ${GITHUB_REPO}."
  else
    log "ERROR: GITHUB_TOKEN or GITHUB_REPO not set. Cannot trigger pipeline. Manual intervention required."
    exit 1
  fi
fi
