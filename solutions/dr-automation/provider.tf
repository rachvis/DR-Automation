##############################################################################
# IBM Cloud Provider - dual-region for DR
##############################################################################

terraform {
  required_providers {
    ibm = {
      source  = "IBM-Cloud/ibm"
      version = ">=1.63.0"
    }
  }
}
