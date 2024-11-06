locals {
  asg_tags = [
    for k, v in local.tags :
    { "key" : k, "value" : v, "propagate_at_launch" = true }
  ]
  asg_control_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" : "owned",
    "zadara.com/k8s/role" : "control",
  }
  asg_worker_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" : "owned",
    "k8s.io/cluster-autoscaler/enabled" : "true",
    "k8s.io/cluster-autoscaler/${var.cluster_name}" : "owned",
    "zadara.com/k8s/role" : "worker",
  }
}

resource "aws_autoscaling_group" "control" {
  for_each             = local.node_groups_control
  name                 = "${substr(var.cluster_name, 0, 32 - length(each.key) - 1)}-${each.key}"
  launch_configuration = aws_launch_configuration.this[each.key].name
  min_size             = each.value.min_size
  desired_capacity     = each.value.desired_capacity
  max_size             = each.value.max_size

  vpc_zone_identifier = try(each.value.subnets, var.subnets)

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [load_balancers, target_group_arns, desired_capacity]
  }
  dynamic "tag" {
    for_each = merge(
      { for k, v in try(each.value.k8s_taints, {}) : "k8s.io/cluster-autoscaler/node-template/taint/${k}" => v },
      { for k, v in try(each.value.k8s_labels, {}) : "k8s.io/cluster-autoscaler/node-template/label/${k}" => v },
      local.tags,
      local.asg_control_tags,
      { "zadara.com/k8s/node_group" : "${each.key}", "zadara.com/k8s/control_plane_group" : "${var.cluster_name}-${each.key}" },
      each.value.tags,
    )
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}

resource "aws_autoscaling_group" "worker" {
  for_each             = local.node_groups_worker
  depends_on           = [aws_autoscaling_group.control]
  name                 = "${substr(var.cluster_name, 0, 32 - length(each.key) - 1)}-${each.key}"
  launch_configuration = aws_launch_configuration.this[each.key].name
  min_size             = each.value.min_size
  desired_capacity     = each.value.desired_capacity
  max_size             = each.value.max_size

  vpc_zone_identifier = try(each.value.subnets, var.subnets)

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [load_balancers, target_group_arns, desired_capacity]
  }
  dynamic "tag" {
    for_each = merge(
      { for k, v in try(each.value.k8s_taints, {}) : "k8s.io/cluster-autoscaler/node-template/taint/${k}" => v },
      { for k, v in try(each.value.k8s_labels, {}) : "k8s.io/cluster-autoscaler/node-template/label/${k}" => v },
      local.tags,
      local.asg_worker_tags,
      { "zadara.com/k8s/node_group" : "${each.key}", "zadara.com/k8s/control_plane_group" : "${aws_autoscaling_group.control[keys(aws_autoscaling_group.control)[0]].name}" },
      each.value.tags,
    )
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = (length(regexall(".*:.*", tag.key)) + length(regexall(".*:.*", tag.value)) == 0) # 12052
    }
  }
}


resource "aws_autoscaling_attachment" "control" {
  for_each = aws_autoscaling_group.control

  autoscaling_group_name = each.value.id
  alb_target_group_arn   = aws_lb_target_group.kube_api.arn
}

