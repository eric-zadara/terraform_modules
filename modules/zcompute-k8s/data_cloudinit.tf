locals {
  cloudinit_os = {
    common = [
      { order = 0, filename = "write-files-profile-d.yaml", content_type = "text/cloud-config", merge_type = "list(append)+dict(recurse_list,allow_delete)+str()",
        content = templatefile("${path.module}/cloud-init/write-files.tftpl.yaml", { write_files = [
          { path = "/etc/profile.d/zadara-ec2.sh", owner = "root:root", permissions = "0644", content = file("${path.module}/files/zadara-ec2.sh") },
      ] }) },
      { order = 10, filename = "setup-os.sh", content_type = "text/x-shellscript", content = join("\n", [for line in split("\n", file("${path.module}/files/setup-os.sh")) : line if length(regexall("^# .*$", line)) == 0]) },
      { order = 19, filename = "wait-for-instance-profile.sh", content_type = "text/x-shellscript", content = join("\n", [for line in split("\n", file("${path.module}/files/wait-for-instance-profile.sh")) : line if length(regexall("^# .*$", line)) == 0]) },
      { order = 30, filename = "setup-helm.sh", content_type = "text/x-shellscript", content = join("\n", [for line in split("\n", file("${path.module}/files/setup-helm.sh")) : line if length(regexall("^# .*$", line)) == 0]) },
    ]
    ubuntu = []
    debian = []
  }
  cloudinit_flavor = {
    k3s = [
      { order = 0, filename = "write-files-k3s.yaml", content_type = "text/cloud-config", merge_type = "list(append)+dict(recurse_list,allow_delete)+str()",
        content = templatefile("${path.module}/cloud-init/write-files.tftpl.yaml", { write_files = [
          { path = "/etc/profile.d/kubeconfig.sh", owner = "root:root", permissions = "0644", content = file("${path.module}/files/k3s/kubeconfig.sh") },
          { path = "/etc/rancher/k3s/kubelet.config", owner = "root:root", permissions = "0644", content = file("${path.module}/files/k3s/kubelet.config") },
          { path = "/etc/systemd/system/cleanup-k3s.service", owner = "root:root", permissions = "0644", content = file("${path.module}/files/k3s/cleanup.service") },
      ] }) },
      { order = 20, filename = "setup-k3s.sh", content_type = "text/x-shellscript", content = join("\n", [for line in split("\n", file("${path.module}/files/k3s/setup.sh")) : line if length(regexall("^# .*$", line)) == 0]) },
    ]
  }
  cloudinit_cfg = {
    k3s-ubuntu = [
    ]
    k3s-debian = [
    ]
  }
}

data "cloudinit_config" "k8s" {
  for_each      = local.node_groups
  gzip          = true
  base64_encode = true

  dynamic "part" {
    for_each = { for idx, obj in concat(
      [
        { order = 0, filename = "write-files-k8s-json.yaml", content_type = "text/cloud-config", merge_type = "list(append)+dict(recurse_list,allow_delete)+str()", content = templatefile("${path.module}/cloud-init/write-files.tftpl.yaml", { write_files = [
          { path = "/etc/zadara/k8s.json", owner = "root:root", permissions = "0640", content = jsonencode({
            cluster_name    = var.cluster_name
            cluster_version = var.cluster_version
            cluster_token   = coalesce(var.cluster_token, random_id.this.hex)
            cluster_role    = try(each.value.role, "worker")
            cluster_kapi    = aws_lb.kube_api.dns_name
            pod_cidr        = var.pod_cidr
            service_cidr    = var.service_cidr
            feature_gates   = try(each.value.feature_gates, [])
            node_labels     = try(each.value.k8s_labels, {})
            node_taints     = try(each.value.k8s_taints, {})
          }) },
          { enabled = (try(each.value.role, "worker") == "control"), path = "/etc/zadara/k8s_helm.json", owner = "root:root", permissions = "0640",
            content = jsonencode({ for k, v in merge(local.cluster_helm_default, var.cluster_helm) : k => merge(try(local.cluster_helm_default[k], {}), try(var.cluster_helm[k], {})) if v != null && try(v.enabled, true) == true })
          },
          { enabled = (try(each.value.role, "worker") == "control" && try(var.etcd_backup, null) != null), path = "/etc/zadara/etcd_backup.json", owner = "root:root", permissions = "0640",
            content = jsonencode(var.etcd_backup)
          },
        ] }) },
      ],
      local.cloudinit_os["common"],
      local.cloudinit_os[split("-", try(each.value.cluster_flavor, var.cluster_flavor))[1]],
      local.cloudinit_flavor[split("-", try(each.value.cluster_flavor, var.cluster_flavor))[0]],
      local.cloudinit_cfg[try(each.value.cluster_flavor, var.cluster_flavor)],
      try(each.value.cloudinit_config, [])
    ) : join("-", [format("%02s", try(obj.order, 99)), obj.filename]) => obj if try(obj.enabled, true) == true }
    content {
      #filename     = part.value.filename
      filename     = part.key
      content_type = part.value.content_type
      content      = part.value.content
      merge_type   = try(part.value.merge_type, "list(append)+dict(recurse_list,allow_delete)+str()")
    }
  }
}
