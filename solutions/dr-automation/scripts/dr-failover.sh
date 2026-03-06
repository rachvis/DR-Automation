#!/usr/bin/env bash
##############################################################################
# DR Failover Script
# Triggered by GitHub Actions pipeline or manually during a DR event.
# Performs: state verification → environment recreation → traffic cutover
##############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/dr-failover.log"
STATUS_FILE="${SCRIPT_DIR}/dr-status.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

##############################################################################
# Logging helpers
##############################################################################
log()  { echo "[${TIMESTAMP}] INFO:  $*" | tee -a "${LOG_FILE}"; }
warn() { echo "[${TIMESTAMP}] WARN:  $*" | tee -a "${LOG_FILE}"; }
err()  { echo "[${TIMESTAMP}] ERROR: $*" | tee -a "${LOG_FILE}"; exit 1; }

##############################################################################
# Required environment variables
##############################################################################
: "${IBMCLOUD_API_KEY:?Must set IBMCLOUD_API_KEY}"
: "${PRIMARY_REGION:?Must set PRIMARY_REGION}"
: "${DR_REGION:?Must set DR_REGION}"
: "${TF_STATE_BUCKET:?Must set TF_STATE_BUCKET}"
: "${PREFIX:?Must set PREFIX}"

log "====== DR FAILOVER INITIATED ======"
log "Primary Region : ${PRIMARY_REGION}"
log "DR Region      : ${DR_REGION}"
log "Prefix         : ${PREFIX}"

##############################################################################
# Step 1 - Authenticate to IBM Cloud
##############################################################################
log "Step 1: Authenticating to IBM Cloud..."
ibmcloud login --apikey "${IBMCLOUD_API_KEY}" -r "${DR_REGION}" -q
ibmcloud target -r "${DR_REGION}"
log "Authentication successful."

##############################################################################
# Step 2 - Retrieve Terraform state from COS
##############################################################################
log "Step 2: Retrieving Terraform state from COS bucket: ${TF_STATE_BUCKET}..."
TFSTATE_PATH="/tmp/dr-terraform.tfstate"
ibmcloud cos object-get \
  --bucket "${TF_STATE_BUCKET}" \
  --key "terraform.tfstate" \
  --output "${TFSTATE_PATH}" || err "Failed to retrieve Terraform state."
log "Terraform state retrieved."

##############################################################################
# Step 3 - Verify DR VSIs are healthy
##############################################################################
log "Step 3: Verifying DR VSI health in ${DR_REGION}..."
DR_VSI_LIST=$(ibmcloud is instances --vpc-name "${PREFIX}-dr-vpc" --output json 2>/dev/null || echo "[]")
DR_VSI_COUNT=$(echo "${DR_VSI_LIST}" | jq '[.[] | select(.status=="running")] | length')

if [[ "${DR_VSI_COUNT}" -lt 1 ]]; then
  warn "No running DR VSIs found. Triggering cold-start provisioning..."
  ##########################################################################
  # Cold start: re-run Terraform to provision DR VSIs from state
  ##########################################################################
  cd /opt/dr-automation/terraform
  terraform init \
    -backend-config="bucket=${TF_STATE_BUCKET}" \
    -backend-config="region=${PRIMARY_REGION}"
  terraform apply -auto-approve \
    -var="ibmcloud_api_key=${IBMCLOUD_API_KEY}" \
    -var="dr_region=${DR_REGION}" \
    -var="prefix=${PREFIX}"
  log "Cold-start provisioning complete."
else
  log "Found ${DR_VSI_COUNT} running DR VSIs. Warm failover proceeding."
fi

##############################################################################
# Step 4 - Generate Ansible dynamic inventory from IBM Cloud API
##############################################################################
log "Step 4: Generating Ansible inventory from DR VSIs..."
INVENTORY_FILE="/tmp/dr-inventory.ini"
echo "[dr_vsis]" > "${INVENTORY_FILE}"

ibmcloud is instances \
  --vpc-name "${PREFIX}-dr-vpc" \
  --output json 2>/dev/null \
  | jq -r '.[] | select(.status=="running") | .primary_network_interface.primary_ipv4_address' \
  | while read -r ip; do
      echo "${ip} ansible_user=ubuntu ansible_ssh_common_args='-o StrictHostKeyChecking=no'" >> "${INVENTORY_FILE}"
    done

log "Ansible inventory written to ${INVENTORY_FILE}."

##############################################################################
# Step 5 - Run Ansible playbook to activate DR workloads
##############################################################################
log "Step 5: Running Ansible failover playbook..."
ansible-playbook \
  -i "${INVENTORY_FILE}" \
  "${SCRIPT_DIR}/../playbooks/activate-dr-workloads.yaml" \
  --extra-vars "primary_region=${PRIMARY_REGION} dr_region=${DR_REGION} prefix=${PREFIX}" \
  | tee -a "${LOG_FILE}"
log "Ansible failover playbook complete."

##############################################################################
# Step 6 - Update DR status
##############################################################################
log "Step 6: Updating DR status to 'active'..."
cat > "${STATUS_FILE}" <<EOF
{
  "status": "active",
  "failover_time": "${TIMESTAMP}",
  "primary_region": "${PRIMARY_REGION}",
  "dr_region": "${DR_REGION}",
  "dr_vsi_count": ${DR_VSI_COUNT}
}
EOF

# Push updated status to COS
ibmcloud cos object-put \
  --bucket "${TF_STATE_BUCKET}" \
  --key "dr-status.json" \
  --body "${STATUS_FILE}" || warn "Could not push DR status to COS."

log "====== DR FAILOVER COMPLETE ======"
log "All DR workloads are now active in ${DR_REGION}."
log "RTO target: ${RTO_MINUTES:-30} minutes."
