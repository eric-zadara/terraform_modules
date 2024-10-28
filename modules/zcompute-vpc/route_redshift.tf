################################################################################
# Redshift routes
################################################################################

resource "aws_route_table" "redshift" {
  count = var.create_vpc && var.create_redshift_subnet_route_table && length(var.redshift_subnets) > 0 ? 1 : 0

  vpc_id = local.vpc_id

  tags = merge(
    {
      "Name" = "${var.name}-${var.redshift_subnet_suffix}"
    },
    var.tags,
    var.redshift_route_table_tags,
  )
}

