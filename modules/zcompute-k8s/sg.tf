locals {
  k8s_sg_rules = {
    ingress_k8s = {
      description = "Allow all intra-cluster traffic"
      protocol    = "all"
      from_port   = 0
      to_port     = 65535
      type        = "ingress"
      self        = true
      #      cidr_blocks = [data.aws_vpc.this.cidr_block]
    }
    egress_k8s = {
      description = "Allow all cluster egress traffic"
      protocol    = "all"
      from_port   = 0
      to_port     = 65535
      type        = "egress"
      self        = true
      #      cidr_blocks = [data.aws_vpc.this.cidr_block]
    }
  }
  k8s_extra_sg_rules = flatten([
    for group_key, config in local.node_groups : [
      for sg_rule_key, rule_config in config.security_group_rules : {
        group_key   = group_key
        sg_rule_key = sg_rule_key
      }
    ]
  ])
}

# General node<->node security group to ensure k8s peer connectivity
resource "aws_security_group" "k8s" {
  name        = "${var.cluster_name}_k8s"
  description = "K8s intra-cluster traffic"
  vpc_id      = data.aws_vpc.this.id

  tags = merge(local.tags, { "kubernetes.io/cluster/${var.cluster_name}" = "owned" })
}

resource "aws_security_group_rule" "k8s" {
  for_each         = local.k8s_sg_rules
  type             = try(each.value.type, null)
  description      = try(each.value.description, null)
  from_port        = try(each.value.from_port, null)
  to_port          = try(each.value.to_port, null)
  protocol         = try(each.value.protocol, null)
  self             = try(each.value.self, null)
  cidr_blocks      = try(each.value.cidr_blocks, null)
  ipv6_cidr_blocks = try(each.value.ipv6_cidr_blocks, null)

  security_group_id = aws_security_group.k8s.id
}

# Per-node-group security groups intended for opening up external connectivity
resource "aws_security_group" "k8s_extra" {
  for_each    = local.node_groups
  name        = "${var.cluster_name}_k8s_${each.key}"
  description = "K8s traffic for ${each.key}"
  vpc_id      = data.aws_vpc.this.id

  tags = local.tags
}
resource "aws_security_group_rule" "k8s_extra" {
  for_each = tomap({
    for entry in local.k8s_extra_sg_rules : "${entry.group_key}.${entry.sg_rule_key}" => entry
  })
  type             = try(local.node_groups[each.value.group_key].security_group_rules[each.value.sg_rule_key].type, null)
  description      = try(local.node_groups[each.value.group_key].security_group_rules[each.value.sg_rule_key].description, null)
  from_port        = try(local.node_groups[each.value.group_key].security_group_rules[each.value.sg_rule_key].from_port, null)
  to_port          = try(local.node_groups[each.value.group_key].security_group_rules[each.value.sg_rule_key].to_port, null)
  protocol         = try(local.node_groups[each.value.group_key].security_group_rules[each.value.sg_rule_key].protocol, null)
  self             = try(local.node_groups[each.value.group_key].security_group_rules[each.value.sg_rule_key].self, null)
  cidr_blocks      = try(local.node_groups[each.value.group_key].security_group_rules[each.value.sg_rule_key].cidr_blocks, null)
  ipv6_cidr_blocks = try(local.node_groups[each.value.group_key].security_group_rules[each.value.sg_rule_key].ipv6_cidr_blocks, null)

  security_group_id = aws_security_group.k8s_extra[split(".", each.key)[0]].id
}
