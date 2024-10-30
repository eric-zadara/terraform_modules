locals {
  debian_lts = [
    {
      codename = "bookworm"
      year     = 2023
      regex    = "Public - Debian 12"
    },
    {
      codename = "bullseye"
      year     = 2021
      regex    = "Public - Debian 11"
    },
    {
      codename = "buster"
      year     = 2019
      regex    = "Public - Debian 10"
    },
    {
      codename = "stretch"
      year     = 2017
      regex    = "Public - Debian 9"
    },
  ]
}

data "aws_ami_ids" "debian" {
  count      = length(local.debian_lts)
  owners     = ["*"]
  name_regex = "^${local.debian_lts[count.index].regex}$"

  filter {
    name   = "is-public"
    values = ["true"]
  }
  filter {
    name   = "state"
    values = ["available"]
  }
}
