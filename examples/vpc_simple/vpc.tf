variable "vpc_name" {
  type        = string
  description = "Display name for the VPC"
}

variable "vpc_cidr" {
  type        = string
  description = "IP CIDR configuration. ex: 10.0.0.0/16"
}

module "vpc" {
  source = "github.com/zadarastorage/terraform-zcompute-vpc?ref=main"
  # It's recommended to change `main` to a specific release version to prevent unexpected changes

  name           = var.vpc_name
  cidr           = var.vpc_cidr
  azs            = ["symphony"]
  public_subnets = [var.vpc_cidr]

  enable_nat_gateway = false

  tags = var.tags
}
