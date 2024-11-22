module "vpc" {
  source = "github.com/eric-zadara/terraform_modules//modules/zcompute-k8s?ref=master"
  # It's recommended to change `master` to a specific release version to prevent unexpected changes

  vpc_id  = module.vpc.vpc_id
  subnets = module.vpc.private_subnets

  tags = {
    my-tag = "my-value"
  }

  cluster_name    = "my-single-node-cluster"
  cluster_version = "1.31.2"
  cluster_helm = {
    cluster-autoscaler = {
      enabled = false
    }
  }

  node_group_defaults = {
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
      min_size     = 1
      max_size     = 1
      desired_size = 1
      feature_gate = ["controlplane-workload"]
    }
  }
}
