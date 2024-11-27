variable "vpc_name" {
  type        = string
  description = "Display name for the VPC"
}

variable "vpc_cidr" {
  type        = string
  description = "IP CIDR configuration. ex: 10.0.0.0/16"
}

variable "vpc_cidr_public" {
  type        = string
  description = "IP CIDR configuration. ex: 10.0.0.0/17"
}

variable "vpc_cidr_private" {
  type        = string
  description = "IP CIDR configuration. ex: 10.0.128.0/17"
}

module "vpc" {
  source = "github.com/eric-zadara/terraform_modules//modules/zcompute-vpc?ref=master"
  # It's recommended to change `master` to a specific release version to prevent unexpected changes

  name            = var.vpc_name
  cidr            = var.vpc_cidr
  azs              = ["symphony"]
  public_subnets  = [var.vpc_cidr_public]
  private_subnets = [var.vpc_cidr_private]

  enable_nat_gateway = true

  tags = var.tags
}
