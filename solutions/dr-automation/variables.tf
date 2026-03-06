##############################################################################
# DR Automation Variables
##############################################################################

variable "ibmcloud_api_key" {
  description = "The IBM Cloud platform API key needed to deploy IAM enabled resources."
  type        = string
  sensitive   = true
}

variable "prefix" {
  description = "A unique identifier for resources. Must begin with a lowercase letter and end with a lowercase letter or number. Prefixes must be 16 or fewer characters."
  type        = string
  default     = "dr-auto"

  validation {
    error_message = "Prefix must begin with a lowercase letter and contain only lowercase letters, numbers, and - characters. Prefixes must end with a lowercase letter or number and be 16 or fewer characters."
    condition     = can(regex("^([a-z]|[a-z][-a-z0-9]*[a-z0-9])$", var.prefix)) && length(var.prefix) <= 16
  }
}

variable "resource_group" {
  description = "Name of the IBM Cloud resource group to deploy DR resources into."
  type        = string
  default     = "Default"
}

##############################################################################
# Region Configuration
##############################################################################

variable "primary_region" {
  description = "The IBM Cloud region of the primary (production) workloads."
  type        = string
  default     = "us-south"
}

variable "dr_region" {
  description = "The IBM Cloud region to use as the Disaster Recovery target region."
  type        = string
  default     = "us-east"
}

variable "primary_vpc_name" {
  description = "Name of the existing primary VPC to replicate for DR."
  type        = string
}

variable "dr_zones" {
  description = "Availability zones within the DR region to spread DR VSIs across."
  type        = list(string)
  default     = ["1", "2", "3"]
}

variable "dr_subnet_cidrs" {
  description = "CIDR blocks for each DR subnet, one per zone."
  type        = list(string)
  default     = ["10.240.64.0/24", "10.240.65.0/24", "10.240.66.0/24"]
}

variable "bastion_cidr" {
  description = "CIDR block of the bastion/jump host allowed to SSH into DR VSIs."
  type        = string
  default     = "10.0.0.0/8"
}

##############################################################################
# VSI Configuration
##############################################################################

variable "ssh_public_key" {
  description = "Public SSH key for DR VSI access. Must be a valid SSH key."
  type        = string
}

variable "ssh_private_key" {
  description = "Private SSH key (RSA format) used by Ansible to configure DR VSIs. Not stored after deployment."
  type        = string
  sensitive   = true
}

variable "vsi_image" {
  description = "OS image name for DR VSIs. Use 'ibmcloud is images' to list available images."
  type        = string
  default     = "ibm-ubuntu-22-04-5-minimal-amd64-1"
}

variable "vsi_profile" {
  description = "VSI machine type profile for DR instances."
  type        = string
  default     = "cx2-2x4"
}

variable "dr_vsi_count" {
  description = "Number of warm standby VSI instances to maintain in the DR region."
  type        = number
  default     = 2

  validation {
    error_message = "DR VSI count must be between 1 and 10."
    condition     = var.dr_vsi_count >= 1 && var.dr_vsi_count <= 10
  }
}

##############################################################################
# DR Automation Configuration
##############################################################################

variable "dr_mode" {
  description = "DR deployment mode. 'warm' keeps standby VSIs running. 'cold' provisions on failover only."
  type        = string
  default     = "warm"

  validation {
    error_message = "DR mode must be 'warm' or 'cold'."
    condition     = contains(["warm", "cold"], var.dr_mode)
  }
}

variable "rto_minutes" {
  description = "Target Recovery Time Objective (RTO) in minutes. Used to configure failover automation timing."
  type        = number
  default     = 30
}

variable "rpo_minutes" {
  description = "Target Recovery Point Objective (RPO) in minutes. Used to configure data replication frequency."
  type        = number
  default     = 15
}

variable "enable_argocd" {
  description = "Whether to install and configure ArgoCD on DR VSIs for GitOps-driven failover."
  type        = bool
  default     = true
}

variable "argocd_repo_url" {
  description = "Git repository URL for ArgoCD to watch and sync application manifests during DR."
  type        = string
  default     = ""
}

variable "github_actions_webhook_secret" {
  description = "Shared secret for GitHub Actions webhook that triggers DR pipeline."
  type        = string
  sensitive   = true
  default     = ""
}

##############################################################################
# Monitoring & Observability
##############################################################################

variable "enable_monitoring" {
  description = "Enable IBM Cloud Monitoring (Sysdig) for DR health checks and alerting."
  type        = bool
  default     = true
}

##############################################################################
# Tags
##############################################################################

variable "tags" {
  description = "Tags to apply to all DR resources."
  type        = list(string)
  default     = ["dr-automation", "vpc-vsi", "gitops"]
}
