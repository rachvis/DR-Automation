# DR Automation for IBM Cloud VPC VSIs
### Terraform + GitOps Deployable Architecture

A fully automated Disaster Recovery solution for IBM Cloud VPC Virtual Server Instances, implementing the modern hyperscaler approach to DR: **infrastructure as code + GitOps orchestration**.

---

## Architecture Overview

```
Primary Region (Production)          DR Region (Standby/Active)
┌─────────────────────────┐          ┌──────────────────────────────┐
│  VPC                    │          │  DR VPC                      │
│  ├── Subnet (Zone 1)    │          │  ├── DR Subnet (Zone 1)      │
│  │   └── VSI(s)         │◄─ sync ─►│  │   └── Warm Standby VSI   │
│  ├── Subnet (Zone 2)    │          │  ├── DR Subnet (Zone 2)      │
│  │   └── VSI(s)         │          │  │   └── Warm Standby VSI   │
│  └── Subnet (Zone 3)    │          │  └── DR Subnet (Zone 3)      │
│      └── VSI(s)         │          │      └── Warm Standby VSI   │
└─────────────────────────┘          └──────────────────────────────┘
         │                                         │
         ▼                                         ▼
┌─────────────────────────────────────────────────────────────────┐
│                    GitOps Control Plane                         │
│                                                                 │
│  GitHub Actions Pipeline                                        │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────────────────┐ │
│  │  Terraform   │  │   Ansible    │  │       ArgoCD          │ │
│  │  (Infra)     │→ │  (Config)    │→ │   (App Sync)          │ │
│  └──────────────┘  └──────────────┘  └───────────────────────┘ │
│          │                                                      │
│          ▼                                                      │
│  IBM Cloud Object Storage (Terraform State)                     │
└─────────────────────────────────────────────────────────────────┘
```

## DR Workflow

```
Infrastructure (Terraform State in COS)
      │
      ▼
DR Pipeline (GitHub Actions - triggered by health check or manually)
      │
      ├── Step 1: Authenticate to IBM Cloud
      ├── Step 2: Retrieve Terraform state from COS
      ├── Step 3: Verify / provision DR VSIs (warm or cold start)
      ├── Step 4: Generate Ansible dynamic inventory
      ├── Step 5: Run Ansible failover playbook (activate workloads)
      └── Step 6: ArgoCD sync (apply GitOps manifests to DR)
      │
      ▼
Recreated Environment Active in DR Region
```

---

## Stack

| Tool | Role |
|------|------|
| **Terraform** | Provisions and manages dual-region VPC infrastructure. State stored in IBM COS. |
| **IBM Cloud Object Storage** | Backend for Terraform state and Ansible dynamic inventory. |
| **Ansible** | Post-deploy VSI configuration; activates workloads during failover. |
| **ArgoCD** | GitOps sync — keeps DR application state aligned with the Git repository. |
| **GitHub Actions** | Orchestrates the full DR pipeline. Triggered by health checks, releases, or manual dispatch. |
| **IBM Cloud Monitoring** | Continuous health checks; provides observability for both primary and DR environments. |

---

## Advantages

- **Cloud-native** — uses IBM Cloud VPC, COS, and Monitoring natively; no third-party DR tools required.
- **Fully automated** — health checks detect primary failure and trigger the DR pipeline without manual intervention.
- **GitOps-driven** — all infrastructure and application state is in Git, providing full auditability and rollback capability.
- **Configurable RTO/RPO** — RTO and RPO targets are first-class configuration parameters.
- **Multi-region** — primary and DR regions are independently configurable across any supported IBM Cloud regions.
- **Compliance-ready** — mapped to IBM Cloud Framework for Financial Services controls (CP-6, CP-7, CP-10).

---

## Solutions

### `solutions/dr-automation` — Core DR Infrastructure (Fullstack)

Provisions all DR infrastructure from scratch:
- DR VPC with subnets across up to 3 availability zones
- Warm standby VSIs pre-configured with the GitOps toolchain
- IBM COS buckets for Terraform state and Ansible inventory
- IBM Cloud Monitoring instance for health observability
- Security groups restricting access to bastion CIDR

### `.github/workflows/dr-pipeline.yml` — GitHub Actions Pipeline

Orchestrates the full DR lifecycle:
- `terraform-plan` → `terraform-apply` → `ansible-configure` → `argocd-sync`
- Triggered on: GitHub release, `workflow_dispatch` (manual or from health check), or weekly scheduled DR test
- Supports actions: `failover`, `failback`, `test`, `status`

---

## Configuration

### Required Variables

| Variable | Description |
|----------|-------------|
| `ibmcloud_api_key` | IBM Cloud API key with VPC Administrator and COS Manager permissions |
| `prefix` | Resource name prefix (≤16 chars, lowercase) |
| `primary_vpc_name` | Name of the existing primary VPC to mirror |
| `primary_region` | IBM Cloud region of production workloads |
| `dr_region` | IBM Cloud region for DR standby environment |
| `ssh_public_key` | SSH public key for DR VSI access |
| `ssh_private_key` | SSH private key used by Ansible (not stored) |

### Optional Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `dr_vsi_count` | `2` | Number of warm standby VSIs |
| `dr_mode` | `warm` | `warm` (VSIs always running) or `cold` (provision on failover) |
| `rto_minutes` | `30` | Recovery Time Objective target |
| `rpo_minutes` | `15` | Recovery Point Objective / health check interval |
| `enable_argocd` | `true` | Install and configure ArgoCD on DR VSIs |
| `enable_monitoring` | `true` | Enable IBM Cloud Monitoring |
| `vsi_profile` | `cx2-2x4` | VSI machine type profile |
| `vsi_image` | `ibm-ubuntu-22-04-5-minimal-amd64-1` | OS image |

### GitHub Actions Secrets Required

| Secret | Description |
|--------|-------------|
| `IBMCLOUD_API_KEY` | IBM Cloud API key |
| `PRIMARY_REGION` | Primary IBM Cloud region |
| `DR_REGION` | DR IBM Cloud region |
| `DR_PREFIX` | Prefix used for DR resource naming |
| `PRIMARY_VPC_NAME` | Name of production VPC |
| `TF_STATE_BUCKET` | COS bucket name for Terraform state |
| `DR_SSH_PUBLIC_KEY` | SSH public key for DR VSIs |
| `DR_SSH_PRIVATE_KEY` | SSH private key for Ansible |
| `ARGOCD_SERVER` | ArgoCD server hostname (if ArgoCD enabled) |
| `ARGOCD_TOKEN` | ArgoCD authentication token |
| `GITHUB_TOKEN` | Auto-provided by GitHub Actions |

---

## Onboarding to IBM Cloud Catalog

The included `ibm_catalog.json` and GitHub Actions workflow (`dr-pipeline.yml`) automate catalog onboarding on every release:

1. Create a GitHub release with a semver tag (e.g. `v1.0.0`).
2. The pipeline runs `onboard_validate_publish.sh` to import, validate, SCC scan, and publish the offering.
3. Cleanup of validation resources runs automatically.

---

## Compliance

This architecture maps to the following IBM Cloud Framework for Financial Services controls:

| Control | Description |
|---------|-------------|
| **CP-6** | Alternate Storage Site |
| **CP-7** | Alternate Processing Site |
| **CP-10** | Information System Recovery and Reconstitution |
| **SI-12** | Information Handling and Retention |
| **SC-6** | Resource Availability |

---

## DR Test Schedule

A non-destructive DR validation runs every Sunday at 02:00 UTC via the scheduled GitHub Actions trigger. It verifies:
- DR VSIs are in `running` state
- DR VPC is reachable
- Terraform state is accessible in COS

No workload activation occurs during scheduled tests.

---

## License

Apache 2.0 — see [LICENSE](./LICENSE)
# DR-Automation
