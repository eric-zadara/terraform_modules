################################################################################
# Internet Gateway
################################################################################

resource "aws_internet_gateway" "this" {
  count = var.create_vpc && var.create_igw && length(var.public_subnets) > 0 ? 1 : 0

  vpc_id = local.vpc_id

  tags = merge(
    {
      "Name" = format("%s", var.name)
    },
    var.tags,
    var.igw_tags,
  )
  depends_on = [aws_route_table.public]
  lifecycle {
    replace_triggered_by = [aws_vpc.this[count.index].id]
  }
}

resource "aws_egress_only_internet_gateway" "this" {
  count = var.create_vpc && var.create_egress_only_igw && var.enable_ipv6 && local.max_subnet_length > 0 ? 1 : 0

  vpc_id = local.vpc_id

  tags = merge(
    {
      "Name" = format("%s", var.name)
    },
    var.tags,
    var.igw_tags,
  )
  depends_on = [aws_route_table.public]
  lifecycle {
    replace_triggered_by = [aws_vpc.this[count.index].id]
  }
}

