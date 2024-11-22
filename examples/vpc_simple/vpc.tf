module "vpc" {
  source = "github.com/eric-zadara/terraform_modules//modules/zcompute-vpc?ref=master"
  # It's recommended to change `master` to a specific release version to prevent unexpected changes

  name           = "my-vpc"
  cidr           = "10.0.0.0/16"
  az             = ["symphony"]
  public_subnets = ["10.0.0.0/16"]

  enable_nat_gateway = false

  tags = {
    my-tag = "my-value"
  }
}
