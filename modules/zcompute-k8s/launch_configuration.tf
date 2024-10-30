# Provider Workaround: aws_launch_configuration appears unable "read" *_block_device configurations from the provider
resource "terraform_data" "aws_launch_configuration" {
  for_each = local.node_groups
  input = {
    "root_volume_size" = try(each.value.root_volume_size, 32)
    "root_volume_type" = try(each.value.root_volume_type, null)
  }
}

resource "aws_launch_configuration" "this" {
  for_each         = local.node_groups
  name_prefix      = "${var.cluster_name}_${each.key}_"
  image_id         = try(each.value.image_id, local.flavor_defaults[try(each.value.cluster_flavor, var.cluster_flavor)].image_id)
  instance_type    = each.value.instance_type
  key_name         = try(each.value.key_name, null)
  user_data_base64 = data.cloudinit_config.k8s[each.key].rendered

  security_groups = [aws_security_group.k8s.id, aws_security_group.k8s_extra[each.key].id, ]

  iam_instance_profile = try(each.value.iam_instance_profile, null)

  root_block_device {
    volume_size           = terraform_data.aws_launch_configuration[each.key].output.root_volume_size
    volume_type           = terraform_data.aws_launch_configuration[each.key].output.root_volume_type
    delete_on_termination = "true"
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [root_block_device]
    replace_triggered_by = [
      terraform_data.aws_launch_configuration[each.key],
    ]
  }
}
