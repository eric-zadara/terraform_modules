data "aws_vpc" "this" {
  id = var.vpc_id
}

#data "aws_subnet_ids" "public" {
#  vpc_id = data.aws_vpc.this.id
#
#  tags = {
#    "kubernetes.io/role/elb" = "1"
#  }
#}
#data "aws_subnet_ids" "private" {
#  vpc_id = data.aws_vpc.this.id
#
#  tags = {
#    "kubernetes.io/role/internal-elb" = "1"
#  }
#}

#data "aws_subnet" "selected" {
#  for_each = toset(sort(concat(
#    flatten(data.aws_subnet_ids.private[*].ids),
#    flatten(data.aws_subnet_ids.public[*].ids)
#  )))
#  id = each.value
#}
