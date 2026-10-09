###############################################################################
# variables.tf
###############################################################################

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment tag (e.g. dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Prefix applied to every resource name"
  type        = string
  default     = "hardened-ec2"
}

variable "key_name" {
  description = "Name of the AWS Key Pair and the local .pem file"
  type        = string
  default     = "hardened-ec2-key"
}

variable "trusted_ip_cidr" {
  description = <<-EOD
    Your public IP in CIDR notation (e.g. \"203.0.113.10/32\").
    ONLY this address will be allowed inbound on ports 22 and 443.
    Run: curl -s https://checkip.amazonaws.com && echo /32
  EOD
  type        = string

  validation {
    condition     = can(cidrnetmask(var.trusted_ip_cidr))
    error_message = "trusted_ip_cidr must be a valid CIDR block (e.g. 203.0.113.10/32)."
  }
}
