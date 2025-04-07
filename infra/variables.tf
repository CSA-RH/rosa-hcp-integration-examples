variable "openshift_version" {
  type    = string
  default = "4.18.5"
  validation {
    condition     = can(regex("^[0-9]*[0-9]+.[0-9]*[0-9]+.[0-9]*[0-9]+$", var.openshift_version))
    error_message = "openshift_version must be with structure <major>.<minor>.<patch> (for example 4.13.6)."
  }
}

variable "cluster_name" {
  type = string  
}

variable "cluster_vpc_cidr" {
  type = string
  default     = "10.0.0.0/16"
  description = "Cidr block of the desired VPC. This value should not be updated, please create a new resource instead"
}

variable "rosa_token" {
  type = string
}

variable "rosa_ocm_url" {
  type = string
  default     = "https://api.openshift.com"
}

variable "aws_billing_account_id" {
  type = string
  nullable =  true
  default = null
}

variable "demo_namespace" {
  type = string
  default = "demo-rosa-terraform"
}