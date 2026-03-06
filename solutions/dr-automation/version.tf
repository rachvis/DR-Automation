terraform {
  required_version = ">= 1.6.0"
  required_providers {
    ibm = {
      source  = "IBM-Cloud/ibm"
      version = ">=1.63.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">=3.4.0"
    }
  }
}
