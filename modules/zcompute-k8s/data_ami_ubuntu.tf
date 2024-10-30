locals {
  ubuntu_lts = [
    {
      codename = "noble"
      year     = 2024
      regex    = "Public - Ubuntu Server 24.04"
    },
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
    {
      codename = "xenial"
      year     = 2016
      regex    = "Public - Ubuntu Server 16.04"
    },
    {
      codename = "trusty"
      year     = 2014
      regex    = "Public - Ubuntu Server 14.04"
    },
  ]
}

data "aws_ami_ids" "ubuntu" {
  count      = length(local.ubuntu_lts)
  owners     = ["*"]
  name_regex = "^${local.ubuntu_lts[count.index].regex}$"

  filter {
    name   = "is-public"
    values = ["true"]
  }
  filter {
    name   = "state"
    values = ["available"]
  }
}
