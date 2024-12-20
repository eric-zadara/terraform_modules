locals {
  cluster_helm_default = {
    zadara-aws-config = {
      order           = 10
      wait            = true
      repository_name = "zadara-charts"
      repository_url  = "https://eric-zadara.github.io/helm_charts"
      chart           = "zadara-aws-config"
      version         = "0.0.3"
      namespace       = "kube-system"
      config          = null
    }
    traefik-elb = {
      order           = 10
      wait            = true
      repository_name = "zadara-charts"
      repository_url  = "https://eric-zadara.github.io/helm_charts"
      chart           = "k3s-helmchartconfig"
      version         = "0.0.2"
      namespace       = "kube-system"
      config = {
        config = {
          traefik = {
            namespace = "kube-system"
            valuesContent = {
              service = {
                annotations = {
                  "service.beta.kubernetes.io/aws-load-balancer-backend-protocol"                    = "tcp"
                  "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type"                     = "instance"
                  "service.beta.kubernetes.io/aws-load-balancer-scheme"                              = "internet-facing"
                  "service.beta.kubernetes.io/aws-load-balancer-type"                                = "external"
                  "service.beta.kubernetes.io/aws-load-balancer-proxy-protocol"                      = "*"
                  "service.beta.kubernetes.io/aws-load-balancer-manage-backend-security-group-rules" = "false"
                  "service.beta.kubernetes.io/aws-load-balancer-security-groups"                     = join(", ", concat([aws_security_group.k8s.id], [for obj in aws_security_group.k8s_extra : obj.id]))
                }
                spec = {
                  externalTrafficPolicy = "Local"
                }
              }
              tolerations = [
                { key = "CriticalAddonsOnly", operator = "Exists" },
              ]
              #ports = {
              #  web = {
              #    proxyProtocol = {
              #      trustedIPs = sort([for key, obj in data.aws_subnet.selected : obj.cidr_block])
              #    }
              #    forwardedHeaders = {
              #      trustedIPs = sort([for key, obj in data.aws_subnet.selected : obj.cidr_block])
              #    }
              #  }
              #  websecure = {
              #    proxyProtocol = {
              #      trustedIPs = sort([for key, obj in data.aws_subnet.selected : obj.cidr_block])
              #    }
              #    forwardedHeaders = {
              #      trustedIPs = sort([for key, obj in data.aws_subnet.selected : obj.cidr_block])
              #    }
              #  }
              #}
            }
          }
        }
      }
    }
    aws-cloud-controller-manager = {
      order           = 11
      wait            = true
      repository_name = "cloud-provider-aws"
      repository_url  = "https://kubernetes.github.io/cloud-provider-aws"
      chart           = "aws-cloud-controller-manager"
      version         = "0.0.8"
      namespace       = "kube-system"
      config = {
        args              = ["--v=2", "--cloud-provider=aws", "--allocate-node-cidrs=false", "--configure-cloud-routes=false", "--cloud-config=/zadara/cloud.conf"]
        nodeSelector      = { "node-role.kubernetes.io/control-plane" = "true" }
        tolerations       = [{ effect = "NoSchedule", key = "", operator = "Exists" }, { effect = "NoExecute", key = "", operator = "Exists" }]
        extraVolumes      = [{ name = "cloud-config", configMap = { name = "cloud-config" } }]
        extraVolumeMounts = [{ mountPath = "/zadara", name = "cloud-config" }]
      }
    }
    calico = {
      order           = 12
      wait            = true
      enabled         = false
      repository_name = "projectcalico",
      repository_url  = "https://docs.tigera.io/calico/charts"
      chart           = "tigera-operator"
      version         = "v3.29.1"
      namespace       = "tigera-operator"
      config = {
        installation = {
          registry = "quay.io/"
          calicoNetwork = {
            containerIPForwarding = "Enabled"
            bgp                   = "Enabled"
            ipPools               = [{ cidr = var.pod_cidr }]
          }
          cni          = { type = "Calico" }
          serviceCIDRs = [var.service_cidr]
        }
      }
    }
    flannel = {
      order           = 12
      wait            = true
      enabled         = true
      repository_name = "flannel",
      repository_url  = "https://flannel-io.github.io/flannel"
      chart           = "flannel"
      version         = "v0.26.2"
      namespace       = "kube-flannel"
      config = {
        podCidr = var.pod_cidr
      }
    }
    aws-ebs-csi-driver = {
      order           = 13
      repository_name = "aws-ebs-csi-driver"
      repository_url  = "https://kubernetes-sigs.github.io/aws-ebs-csi-driver"
      chart           = "aws-ebs-csi-driver"
      version         = "2.35.0"
      namespace       = "kube-system"
      config = {
        controller = {
          region = "us-east-1"
        }
        sidecars = {
          provisioner = {
            additionalArgs = ["--extra-create-metadata", "--timeout=120s", "--retry-interval-start=10s"]
          }
          attacher = {
            additionalArgs = ["--timeout=120s", "--retry-interval-start=10s"]
          }
        }
        storageClasses = [
          {
            name                 = "gp3"
            volumeBindingMode    = "WaitForFirstConsumer"
            allowVolumeExpansion = true
            parameters = {
              type               = "gp3"
              tagSpecification_1 = "Name={{ .PVName }}"
            }
            mountOptions = [
              "errors=panic"
            ]
            annotations = {
              "storageclass.kubernetes.io/is-default-class" = "true"
            }
          }
        ]
        volumeSnapshotClasses = [
          {
            name           = "gp3"
            deletionPolicy = "Delete"
            parameters = {
              type               = "gp3"
              tagSpecification_1 = "Name={{ .PVName }}"
            }
            annotations = {
              "storageclass.kubernetes.io/is-default-class" = "true"
            }
          }
        ]
      }
    }
    cluster-autoscaler = {
      order           = 14
      repository_name = "autoscaler"
      repository_url  = "https://kubernetes.github.io/autoscaler"
      chart           = "cluster-autoscaler"
      version         = "9.38.0"
      namespace       = "kube-system"
      config = {
        awsRegion = "us-east-1"
        autoDiscovery = {
          clusterName = var.cluster_name
        }
        cloudConfigPath   = "/zadara/cloud.conf"
        nodeSelector      = { "node-role.kubernetes.io/control-plane" = "true" }
        tolerations       = [{ effect = "NoSchedule", key = "", operator = "Exists" }, { effect = "NoExecute", key = "", operator = "Exists" }]
        extraVolumes      = [{ name = "cloud-config", configMap = { name = "cloud-config" } }]
        extraVolumeMounts = [{ mountPath = "/zadara", name = "cloud-config" }]
        extraArgs = {
          stderrthreshold = "0"
        }
      }
    }
    aws-load-balancer-controller = {
      order           = 15
      wait            = true
      repository_name = "eks-charts"
      repository_url  = "https://aws.github.io/eks-charts"
      chart           = "aws-load-balancer-controller"
      version         = "1.7.2"
      namespace       = "kube-system"
      config = {
        clusterName = var.cluster_name
        controllerConfig = {
          featureGates = {
            ALBSingleSubnet        = true
            SubnetsClusterTagCheck = false
          }
        }
        ingressClassConfig = { default = true }
        enableShield       = false
        enableWaf          = false
        enableWafv2        = false
        awsApiEndpoints    = "ec2=https://cloud.zadara.com/api/v2/aws/ec2,elasticloadbalancing=https://cloud.zadara.com/api/v2/aws/elbv2,acm=https://cloud.zadara.com/api/v2/aws/acm,sts=https://cloud.zadara.com/api/v2/aws/sts"
        # 1.8.x+ awsApiEndpoints = "EC2=https://cloud.zadara.com/api/v2/aws/ec2,Elastic Load Balancing v2=https://cloud.zadara.com/api/v2/aws/elbv2,ACM=https://cloud.zadara.com/api/v2/aws/acm,STS=https://cloud.zadara.com/api/v2/aws/sts"
        tolerations = [{ effect = "NoSchedule", key = "", operator = "Exists" }, { effect = "NoExecute", key = "", operator = "Exists" }]
      }
    }
  }
}
