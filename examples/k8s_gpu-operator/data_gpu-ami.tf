locals {
  ami_options = [
    {
      codename = "jammy"
      year     = 2022
      regex    = "Public - Ubuntu Server 22.04"
    },
    {
      codename = "focal"
      year     = 2020
      regex    = "Public - Ubuntu Server 20.04"
    },
    {
      codename = "bionic"
      year     = 2018
      regex    = "Public - Ubuntu Server 18.04"
    },
  ]
}

data "aws_ami_ids" "gpu-ubuntu" {
  count      = length(local.ami_options)
  owners     = ["*"]
  name_regex = "^${local.ami_options[count.index].regex}$"

  filter {
    name   = "is-public"
    values = ["true"]
  }
  filter {
    name   = "state"
    values = ["available"]
  }
}
