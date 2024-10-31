locals {
  setup_cfg = [
    { filename = "cloud-config-00.yaml", content_type = "text/cloud-config", merge_type = "list(append)+dict(recurse_list,allow_delete)+str()", content = templatefile("${path.module}/cloud-init/write-files.tftpl.yaml", { write_files = [
      { path = "/etc/zadara/k8s.json", owner = "root:root", permissions = "0640", content = jsonencode({
        cluster_name    = var.cluster_name
        cluster_version = var.cluster_version
        cluster_token   = coalesce(var.cluster_token, random_id.this.hex)
        cluster_role    = try(each.value.role, "worker")
        cluster_kapi    = aws_lb.kube_api.dns_name
      }) },
      { enabled = (try(each.value.role, "worker") == "control"), path = "/etc/zadara/k8s_helm.json", owner = "root:root", permissions = "0640", content = jsonencode({ for k, v in merge(var.cluster_helm, local.cluster_helm_default) : k => v if v != null && try(v.enabled, true) == true }) },
    ] }) },
  ]
  cloudinit_cfg = {
    k3s-ubuntu = [
      { filename = "cloud-config-01.yaml", content_type = "text/cloud-config", merge_type = "list(append)+dict(recurse_list,allow_delete)+str()", content = templatefile("${path.module}/cloud-init/write-files.tftpl.yaml", { write_files = [
        { path = "/etc/profile.d/k3s-kubeconfig.sh", owner = "root:root", permissions = "0644", content = file("${path.module}/files/k3s-kubeconfig.sh") },
        { path = "/etc/profile.d/zadara-ec2.sh", owner = "root:root", permissions = "0644", content = file("${path.module}/files/zadara-ec2.sh") },
      ] }) },
      { filename = "setup-01-k3s.sh", content_type = "text/x-shellscript", content = join("\n", [for line in split("\n", file("${path.module}/files/setup-k3s.sh")) : line if length(regexall("^# .*$", line)) == 0]) },
      { filename = "setup-02-helm.sh", content_type = "text/x-shellscript", content = join("\n", [for line in split("\n", file("${path.module}/files/setup-helm.sh")) : line if length(regexall("^# .*$", line)) == 0]) },
    ]
    k3s-debian = [
      { filename = "cloud-config-01.yaml", content_type = "text/cloud-config", merge_type = "list(append)+dict(recurse_list,allow_delete)+str()", content = templatefile("${path.module}/cloud-init/write-files.tftpl.yaml", { write_files = [
        { path = "/etc/profile.d/k3s-kubeconfig.sh", owner = "root:root", permissions = "0644", content = file("${path.module}/files/k3s-kubeconfig.sh") },
        { path = "/etc/profile.d/zadara-ec2.sh", owner = "root:root", permissions = "0644", content = file("${path.module}/files/zadara-ec2.sh") },
      ] }) },
      { filename = "setup-01-k3s.sh", content_type = "text/x-shellscript", content = join("\n", [for line in split("\n", file("${path.module}/files/setup-k3s.sh")) : line if length(regexall("^# .*$", line)) == 0]) },
      { filename = "setup-02-helm.sh", content_type = "text/x-shellscript", content = join("\n", [for line in split("\n", file("${path.module}/files/setup-helm.sh")) : line if length(regexall("^# .*$", line)) == 0]) },
    ]
  }
}

data "cloudinit_config" "k8s" {
  for_each      = local.node_groups
  gzip          = true
  base64_encode = true

  dynamic "part" {
    for_each = { for idx, obj in concat(
      local.setup_cfg,
      local.cloudinit_cfg[try(each.value.cluster_flavor, var.cluster_flavor)],
      try(each.value.cloudinit_config, [])
    ) : idx => obj if try(obj.enabled, true) == false }
    content {
      filename     = part.value.filename
      content_type = part.value.content_type
      content      = part.value.content
      merge_type   = try(part.value.merge_type, "list(append)+dict(recurse_list,allow_delete)+str()")
    }
  }
}
