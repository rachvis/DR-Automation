##############################################################################
# DR Automation Outputs
##############################################################################

output "prefix" {
  value       = var.prefix
  description = "Prefix used to name DR resources in this deployment."
}

output "primary_region" {
  value       = var.primary_region
  description = "IBM Cloud region of the primary production workloads."
}

output "dr_region" {
  value       = var.dr_region
  description = "IBM Cloud region designated as the Disaster Recovery target."
}

output "dr_vpc_id" {
  description = "ID of the DR VPC created in the DR region."
  value       = ibm_is_vpc.dr_vpc.id
}

output "dr_vpc_name" {
  description = "Name of the DR VPC."
  value       = ibm_is_vpc.dr_vpc.name
}

output "dr_subnet_ids" {
  description = "List of DR subnet IDs across availability zones."
  value       = ibm_is_subnet.dr_subnets[*].id
}

output "dr_vsi_ids" {
  description = "List of DR (warm standby) VSI instance IDs."
  value       = ibm_is_instance.dr_vsis[*].id
}

output "dr_vsi_ips" {
  description = "Primary private IP addresses of all DR VSIs."
  value       = ibm_is_instance.dr_vsis[*].primary_network_interface[0].primary_ipv4_address
}

output "dr_ssh_key_id" {
  description = "ID of the SSH key used for DR VSI access."
  value       = ibm_is_ssh_key.dr_ssh_key.id
}

output "cos_instance_id" {
  description = "CRN of the Cloud Object Storage instance used for Terraform state and Ansible inventory."
  value       = ibm_resource_instance.cos_instance.id
}

output "terraform_state_bucket" {
  description = "Name of the COS bucket storing Terraform state for GitOps pipeline."
  value       = ibm_cos_bucket.terraform_state.bucket_name
}

output "ansible_inventory_bucket" {
  description = "Name of the COS bucket storing Ansible dynamic inventory files."
  value       = ibm_cos_bucket.ansible_inventory.bucket_name
}

output "monitoring_instance_id" {
  description = "CRN of the IBM Cloud Monitoring instance (if enabled)."
  value       = var.enable_monitoring ? ibm_resource_instance.monitoring[0].id : null
}

output "dr_mode" {
  description = "The DR mode configured for this deployment (warm or cold)."
  value       = var.dr_mode
}

output "rto_minutes" {
  description = "Configured Recovery Time Objective in minutes."
  value       = var.rto_minutes
}

output "rpo_minutes" {
  description = "Configured Recovery Point Objective in minutes."
  value       = var.rpo_minutes
}
