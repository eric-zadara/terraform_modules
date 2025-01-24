variable "k8s_name" {
  type        = string
  description = "Display name for the k8s cluster"
}

variable "k8s_version" {
  type        = string
  description = "Version of k8s to use"
  default     = "1.31.2"
}

module "k8s" {
  source = "github.com/zadarastorage/terraform-zcompute-k8s?ref=main"
  # It's recommended to change `main` to a specific release version to prevent unexpected changes

  vpc_id  = module.vpc.vpc_id
  subnets = module.vpc.private_subnets

  tags = var.tags

  cluster_name    = var.k8s_name
  cluster_version = var.k8s_version
  cluster_helm = {
    gpu-operator = {
      order           = 30
      wait            = true
      repository_name = "nvidia"
      repository_url  = "https://helm.ngc.nvidia.com/nvidia"
      chart           = "gpu-operator"
      version         = "v24.6.1"
      namespace       = "gpu-operator"
      config = {
        driver = {
          enabled   = true
          resources = { requests = { cpu = "0.01", memory : "6Gi" } }
        }
        toolkit = { enabled = true }
        devicePlugin = {
          config = {
            create  = true
            name    = "device-plugin-configs"
            default = "any"
            data = {
              # Tesla A16
              tesla-25b6 = yamlencode({
                version = "v1"
                flags   = { migStrategy = "none" }
                sharing = { timeSlicing = {
                  failRequestsGreaterThanOne = false
                  resources                  = [{ name = "nvidia.com/gpu", replicas = 17 }]
                } }
              })
              # Tesla A40
              tesla-2235 = yamlencode({
                version = "v1"
                flags   = { migStrategy = "none" }
                sharing = { timeSlicing = {
                  failRequestsGreaterThanOne = false
                  resources                  = [{ name = "nvidia.com/gpu", replicas = 49 }]
                } }
              })
              # Tesla L4
              tesla-27b8 = yamlencode({
                version = "v1"
                flags   = { migStrategy = "none" }
                sharing = { timeSlicing = {
                  failRequestsGreaterThanOne = false
                  resources                  = [{ name = "nvidia.com/gpu", replicas = 25 }]
                } }
              })
              # Tesla L40S
              tesla-26b9 = yamlencode({
                version = "v1"
                flags   = { migStrategy = "none" }
                sharing = { timeSlicing = {
                  failRequestsGreaterThanOne = false
                  resources                  = [{ name = "nvidia.com/gpu", replicas = 49 }]
                } }
              })
            }
          }
        }
        nfd = { enabled = true }
        node-feature-discovery = {
          worker = {
            config = {
              sources = {
                custom = [{
                  name           = "gpu-timeslice"
                  labelsTemplate = "{{ range .pci.device }}nvidia.com/device-plugin.config=tesla-{{ .device }}{{ end }}"
                  matchFeatures = [{
                    feature = "pci.device"
                    matchExpressions = {
                      class  = { op = "InRegexp", value = ["^03"] }
                      vendor = ["10de"]
                    }
                  }]
                }]
              }
            }
          }
        }
      }
    }
  }

  node_group_defaults = {
    root_volume_size     = 64
    cluster_flavor       = "k3s-ubuntu"
    iam_instance_profile = module.iam-instance-profile.instance_profile_name
    security_group_rules = {
      egress_ipv4 = {
        description = "Allow all outbound ipv4 traffic"
        protocol    = "all"
        from_port   = 0
        to_port     = 65535
        type        = "egress"
        cidr_blocks = ["0.0.0.0/0"]
      }
    }
    key_name = aws_key_pair.this.key_name
    cloudinit_config = [
      {
        order        = 5
        filename     = "cloud-config-registry.yaml"
        content_type = "text/cloud-config"
        content = join("\n", ["#cloud-config", yamlencode({ write_files = [
          { path = "/etc/rancher/k3s/registries.yaml", owner = "root:root", permissions = "0640", encoding = "b64", content = base64encode(yamlencode({
            configs = {}
            mirrors = {
              "*" = {}
              "docker.io" = {
                endpoint = ["https://mirror.gcr.io"]
              }
            }
          })) },
        ] })])
      },
    ]
  }

  node_groups = {
    control = {
      role         = "control"
      min_size     = 3
      max_size     = 3
      desired_size = 3
    }
    worker = {
      role         = "worker"
      min_size     = 1
      max_size     = 3
      desired_size = 1
    }
    gpu = {
      role          = "worker"
      min_size      = 0
      max_size      = 3
      desired_size  = 1
      instance_type = "A02.4xLarge" # TODO Adjust to formalized instance_type name
      k8s_taints = {
        "nvidia.com/gpu" = "true:NoSchedule"
      }
      k8s_labels = {
        "tesla-a16"                       = "true"
        "nvidia.com/gpu"                  = "true"
        "nvidia.com/device-plugin.config" = "tesla-25b6"
        "nvidia.com/gpu.deploy.driver"    = "false"
      }
      tags = {
        "k8s.io/cluster-autoscaler/node-template/resources/nvidia.com/gpu" = "17"
        "nvidia.com/device-plugin.config"                                  = "tesla-25b6"
      }
      cloudinit_config = [
        {
          order        = 11
          filename     = "setup-gpu.sh"
          content_type = "text/x-shellscript"
          content      = file("${path.module}/files/setup-gpu.sh")
        }
      ]
    }
  }
}
