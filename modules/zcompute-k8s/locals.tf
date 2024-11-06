locals {
  tags = merge(
    var.tags,
  )

  tags_list = [
    for k, v in local.tags :
    { "key" : k, "value" : v }
  ]

  node_group_defaults = {
    enabled          = true
    desired_capacity = 0
    instance_type    = "z4.large"
    root_volume_size = 40
    root_volume_type = null
    key_name         = null
    tags             = {}
    feature_gates    = []
    security_group_rules = {
      #ingress_intracluster_allow = {
      #  description = "Allow all intra-cluster ingress traffic"
      #  protocol    = "all"
      #  from_port   = 0
      #  to_port     = 65535
      #  type        = "ingress"
      #  self        = true
      #}
      #egress_intracluster_allow = {
      #  description = "Allow all intra-cluster egress traffic"
      #  protocol    = "all"
      #  from_port   = 0
      #  to_port     = 65535
      #  type        = "egress"
      #  self        = true
      #}
    }
  }

  node_groups = {
    for k, v in var.node_groups :
    k => merge(
      local.node_group_defaults,
      var.node_group_defaults,
      v,
      { security_group_rules = merge(
        lookup(local.node_group_defaults, "security_group_rules", {}),
        lookup(var.node_group_defaults, "security_group_rules", {}),
        lookup(v, "security_group_rules", {}),
      ) },
      { tags = merge(
        lookup(local.node_group_defaults, "tags", {}),
        lookup(var.node_group_defaults, "tags", {}),
        lookup(v, "tags", {}),
      ) },
    )
  }

  node_groups_control = {
    for k, v in local.node_groups :
    k => v if v.enabled && v.role == "control"
  }
  node_groups_worker = {
    for k, v in local.node_groups :
    k => v if v.enabled && v.role == "worker"
  }
  flavor_defaults = {
    k3s-ubuntu = {
      image_id = flatten(data.aws_ami_ids.ubuntu[*].ids)[0]
    }
    k3s-debian = {
      image_id = flatten(data.aws_ami_ids.debian[*].ids)[0]
    }
  }
}
