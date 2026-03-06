##############################################################################
# DR Automation - IBM Cloud VPC VSI
# Terraform + GitOps Deployable Architecture
##############################################################################

terraform {
  required_providers {
    ibm = {
      source  = "IBM-Cloud/ibm"
      version = ">=1.63.0"
    }
  }
}

provider "ibm" {
  ibmcloud_api_key = var.ibmcloud_api_key
  region           = var.primary_region
}

provider "ibm" {
  alias            = "dr_region"
  ibmcloud_api_key = var.ibmcloud_api_key
  region           = var.dr_region
}

##############################################################################
# Primary Region - Source VPC & VSIs
##############################################################################

data "ibm_resource_group" "resource_group" {
  name = var.resource_group
}

# Primary VPC (existing or looked up)
data "ibm_is_vpc" "primary_vpc" {
  name = var.primary_vpc_name
}

data "ibm_is_instances" "primary_vsis" {
  vpc_name = var.primary_vpc_name
}

##############################################################################
# DR Region - Target VPC Infrastructure
##############################################################################

resource "ibm_is_vpc" "dr_vpc" {
  provider       = ibm.dr_region
  name           = "${var.prefix}-dr-vpc"
  resource_group = data.ibm_resource_group.resource_group.id
  tags           = concat(var.tags, ["dr-automation", "terraform-gitops"])
}

resource "ibm_is_public_gateway" "dr_gateway" {
  provider       = ibm.dr_region
  count          = length(var.dr_zones)
  name           = "${var.prefix}-dr-pgw-${var.dr_zones[count.index]}"
  vpc            = ibm_is_vpc.dr_vpc.id
  zone           = "${var.dr_region}-${var.dr_zones[count.index]}"
  resource_group = data.ibm_resource_group.resource_group.id
  tags           = var.tags
}

resource "ibm_is_subnet" "dr_subnets" {
  provider        = ibm.dr_region
  count           = length(var.dr_zones)
  name            = "${var.prefix}-dr-subnet-${var.dr_zones[count.index]}"
  vpc             = ibm_is_vpc.dr_vpc.id
  zone            = "${var.dr_region}-${var.dr_zones[count.index]}"
  ipv4_cidr_block = var.dr_subnet_cidrs[count.index]
  resource_group  = data.ibm_resource_group.resource_group.id
  public_gateway  = ibm_is_public_gateway.dr_gateway[count.index].id
  tags            = var.tags
}

##############################################################################
# DR Security Group
##############################################################################

resource "ibm_is_security_group" "dr_vsi_sg" {
  provider       = ibm.dr_region
  name           = "${var.prefix}-dr-vsi-sg"
  vpc            = ibm_is_vpc.dr_vpc.id
  resource_group = data.ibm_resource_group.resource_group.id
  tags           = var.tags
}

resource "ibm_is_security_group_rule" "dr_sg_ssh" {
  provider  = ibm.dr_region
  group     = ibm_is_security_group.dr_vsi_sg.id
  direction = "inbound"
  remote    = var.bastion_cidr
  tcp {
    port_min = 22
    port_max = 22
  }
}

resource "ibm_is_security_group_rule" "dr_sg_outbound" {
  provider  = ibm.dr_region
  group     = ibm_is_security_group.dr_vsi_sg.id
  direction = "outbound"
  remote    = "0.0.0.0/0"
}

##############################################################################
# DR VSI Instances (Warm Standby)
##############################################################################

data "ibm_is_image" "dr_image" {
  provider = ibm.dr_region
  name     = var.vsi_image
}

resource "ibm_is_ssh_key" "dr_ssh_key" {
  provider       = ibm.dr_region
  name           = "${var.prefix}-dr-ssh-key"
  public_key     = var.ssh_public_key
  resource_group = data.ibm_resource_group.resource_group.id
  tags           = var.tags
}

resource "ibm_is_instance" "dr_vsis" {
  provider       = ibm.dr_region
  count          = var.dr_vsi_count
  name           = "${var.prefix}-dr-vsi-${count.index + 1}"
  image          = data.ibm_is_image.dr_image.id
  profile        = var.vsi_profile
  vpc            = ibm_is_vpc.dr_vpc.id
  zone           = "${var.dr_region}-${var.dr_zones[count.index % length(var.dr_zones)]}"
  resource_group = data.ibm_resource_group.resource_group.id
  keys           = [ibm_is_ssh_key.dr_ssh_key.id]
  tags           = concat(var.tags, ["dr-standby"])

  primary_network_interface {
    subnet          = ibm_is_subnet.dr_subnets[count.index % length(var.dr_zones)].id
    security_groups = [ibm_is_security_group.dr_vsi_sg.id]
  }

  boot_volume {
    name = "${var.prefix}-dr-vsi-${count.index + 1}-boot"
  }
}

##############################################################################
# Cloud Object Storage - Terraform State Backend
##############################################################################

resource "ibm_resource_instance" "cos_instance" {
  name              = "${var.prefix}-dr-cos"
  resource_group_id = data.ibm_resource_group.resource_group.id
  service           = "cloud-object-storage"
  plan              = "standard"
  location          = "global"
  tags              = var.tags
}

resource "ibm_cos_bucket" "terraform_state" {
  bucket_name          = "${var.prefix}-dr-tfstate-${random_id.bucket_suffix.hex}"
  resource_instance_id = ibm_resource_instance.cos_instance.id
  region_location      = var.primary_region
  storage_class        = "smart"
}

resource "ibm_cos_bucket" "ansible_inventory" {
  bucket_name          = "${var.prefix}-dr-ansible-${random_id.bucket_suffix.hex}"
  resource_instance_id = ibm_resource_instance.cos_instance.id
  region_location      = var.primary_region
  storage_class        = "smart"
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

##############################################################################
# IBM Cloud Monitoring - DR Health Checks
##############################################################################

resource "ibm_resource_instance" "monitoring" {
  count             = var.enable_monitoring ? 1 : 0
  name              = "${var.prefix}-dr-monitoring"
  resource_group_id = data.ibm_resource_group.resource_group.id
  service           = "sysdig-monitor"
  plan              = "graduated-tier"
  location          = var.primary_region
  tags              = var.tags
}
