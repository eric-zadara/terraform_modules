module "vpc" {
  source = "github.com/eric-zadara/terraform_modules//modules/zcompute-k8s?ref=master"
  # It's recommended to change `master` to a specific release version to prevent unexpected changes

  vpc_id  = module.vpc.vpc_id
  subnets = module.vpc.private_subnets

  tags = {
    my-tag = "my-value"
  }

  cluster_name    = "my-cluster"
  cluster_version = "1.31.2"
  cluster_helm = {
    gpu-operator = {
      order           = 90
      wait            = true
      repository_name = "nvidia"
      repositry_url   = "https://helm.ngc.nvidia.com/nvidia"
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
                sharing = {
                  timeSlicing = {
                    failRequestsGreaterThanOne = false
                    resources                  = [{ name = "nvidia.com/gpu", replicas = 17 }]
                  }
                }
              })
            }
          }
        }
        nfs = { enabled = true }
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
      instance_type = "A02.4xlarge"
      image_id      = flatten(data.aws_ami_ids.gpu-ubuntu[*].ids)[0]
      k8s_taints = {
        "nvidia.com/gpu" = "true:NoSchedule"
      }
      k8s_labels = {
        "tesla-a16"                       = "true"
        "nvidia.com/gpu"                  = "true"
        "nvidia.com/device-plugin.config" = "tesla-25b6"
      }
      tags = {
        "k8s.io/cluster-autoscaler/node-template/resources/nvidia.com/gpu" = "17"
        "nvidia.com/device-plugin.config"                                  = "tesla-25b6"
      }
    }
  }
}
