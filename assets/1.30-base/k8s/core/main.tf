locals {
  name   = "ex-${basename(path.cwd)}"
  region = "us-east-1"

  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/aws-ia/terraform-aws-eks-blueprints"
  }
}

# Required for public ECR where Karpenter artifacts are hosted
provider "aws" {
  region = "us-east-1"
  alias  = "virginia"
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    # This requires the awscli to be installed locally where Terraform is executed
    args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

provider "kubectl" {
  apply_retry_count      = 5
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  load_config_file       = false

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    # This requires the awscli to be installed locally where Terraform is executed
    args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      # This requires the awscli to be installed locally where Terraform is executed
      args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.virginia
}

################################################################################
# Cluster
################################################################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.24.3"

  cluster_name                   = local.name
  cluster_version                = var.cluster_version
  
  cluster_endpoint_public_access = true
  cluster_endpoint_private_access = true

  cluster_enabled_log_types = ["api", "audit", "controllerManager", "scheduler"]

  # Give the Terraform identity admin access to the cluster
  # which will allow resources to be deployed into the cluster
  enable_cluster_creator_admin_permissions = true

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnets_ids

  eks_managed_node_group_defaults = {
    iam_role_additional_policies = {
      # Not required, but used in the example to access the nodes to inspect mounted volumes
      AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    }
  }

  eks_managed_node_groups = {
    karpenter = {
      platform = "bottlerocket"
      #ami_type       = "BOTTLEROCKET_x86_64"
      ami_type       = "BOTTLEROCKET_ARM_64"
      instance_types = ["m6g.large", "m7g.large"]
      #node_role_arn   = aws_iam_role.node.arn

      iam_role_attach_cni_policy = true
      #ami_id = "ami-080c3912eda75429a"
      ami_release_version = "1.27.1-efd46c32" #"1.26.1-943d9a41"
      capacity_type  = "ON_DEMAND"

      min_size     = 2
      max_size     = 2
      desired_size = 2

      labels = {
        # Used to ensure Karpenter runs on nodes that it does not manage
        "karpenter.sh/controller" = "true"
      }

      taints = {
        # The pods that do not tolerate this taint should run on nodes
        # created by Karpenter
        karpenter = {
          key    = "karpenter.sh/controller"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      }

      block_device_mappings = {
        # Root volume
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_type           = "gp3"
            delete_on_termination = true
            volume_size = 4
          }
        }
        xvdb = {
          # This will be used for containerd's data directory
          device_name = "/dev/xvdb"
          ebs = {
            volume_size           = 20
            volume_type           = "gp3"
            iops                  = 3000
            delete_on_termination = true
          }
        }
      }
    }
  }

  cluster_addons = {
    coredns = {
      addon_version = "v1.11.3-eksbuild.2"
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
      configuration_values = jsonencode({
        tolerations = [
          # Allow CoreDNS to run on the same nodes as the Karpenter controller
          # for use during cluster creation when Karpenter nodes do not yet exist
          {
            key    = "karpenter.sh/controller"
            value  = "true"
            effect = "NoSchedule"
          }
        ]
        #corefile = "dynatrace.com:53 {\n    errors\n    cache 30\n    forward . 10.20.0.2\n    reload\n}\n.:53 {\n    log\n    errors\n    health {\n        lameduck 5s\n      }\n    ready\n    kubernetes cluster.local in-addr.arpa ip6.arpa {\n      pods insecure\n      fallthrough in-addr.arpa ip6.arpa\n    }\n    prometheus :9153\n    forward . /etc/resolv.conf\n    cache 30\n    loop\n    reload\n    loadbalance\n}"
        #corefile = "dynatrace.com:53 {\n    log\n    errors\n    forward . 10.20.0.2\n    cache 30\n}\n.:53 {\n    log\n    errors\n    health {\n        lameduck 5s\n      }\n    ready\n    kubernetes cluster.local in-addr.arpa ip6.arpa {\n      pods insecure\n      fallthrough in-addr.arpa ip6.arpa\n    }\n    prometheus :9153\n    forward . /etc/resolv.conf\n    cache 30\n    loop\n    reload\n    loadbalance\n}"
        corefile = ".:53 {\n    log\n    autopath @kubernetes\n    errors\n    health {\n        lameduck 30s\n      }\n    ready\n    kubernetes cluster.local in-addr.arpa ip6.arpa {\n      pods verified\n      fallthrough in-addr.arpa ip6.arpa\n    }\n    prometheus :9153\n    forward . /etc/resolv.conf\n    cache 30\n    loop\n    reload\n    loadbalance\n}"
        #corefile = "dynatrace.com:53 {\n    log\n    errors\n    forward . 10.20.0.2\n    cache 30\n}\n.:53 {\n    log\n    autopath @kubernetes\n    errors\n    health {\n        lameduck 5s\n      }\n    ready\n    kubernetes cluster.local in-addr.arpa ip6.arpa {\n      pods verified\n      fallthrough in-addr.arpa ip6.arpa\n    }\n    prometheus :9153\n    forward . /etc/resolv.conf\n    cache 30\n    loop\n    reload\n    loadbalance\n}"
      })
    }
    eks-pod-identity-agent = {
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
      addon_version = "v1.3.4-eksbuild.1"
    }
    vpc-cni = {
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
      addon_version = "v1.19.0-eksbuild.1"
    }
    kube-proxy = {
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
      addon_version = "v1.30.6-eksbuild.3"
    }
    aws-ebs-csi-driver = {
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
      addon_version = "v1.37.0-eksbuild.1"
    }
    aws-efs-csi-driver = {
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
      addon_version = "v2.1.0-eksbuild.1"
    }
  }

  # List of map_roles
  #map_roles = [
  #  {
  #    rolearn  = "arn:aws:iam::800651494222:role/AWSReservedSSO_AdministratorAccess_150f806a0138c23c"
  #    username = "platform-admins"
  #    groups   = ["system:masters"]
  #  }
  #]

  tags = merge(local.tags, {
    # NOTE - if creating multiple security groups with this module, only tag the
    # security group that Karpenter should utilize with the following tag
    # (i.e. - at most, only one security group should have this tag in your account)
    "karpenter.sh/discovery" = local.name
  })
}

################################################################################
# Controller & Node IAM roles, SQS Queue, Eventbridge Rules
################################################################################

module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 20.24.3"

  cluster_name = module.eks.cluster_name

  enable_v1_permissions = true

  # Attach additional IAM policies to the Karpenter node IAM role
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  # Name needs to match role name passed to the EC2NodeClass
  node_iam_role_use_name_prefix   = false
  node_iam_role_name              = local.name #"karpenter-eks-node-group-20240625170437362500000002"

  enable_pod_identity             = true
  create_pod_identity_association = true

  tags = local.tags
}

module "karpenter_disabled" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 20.24.3"

  create = false
}

################################################################################
# Helm charts
################################################################################

resource "helm_release" "karpenter" {
  namespace           = "kube-system"
  name                = "karpenter"
  repository          = "oci://public.ecr.aws/karpenter"
  repository_username = data.aws_ecrpublic_authorization_token.token.user_name
  repository_password = data.aws_ecrpublic_authorization_token.token.password
  chart               = "karpenter"
  version             = "1.0.6"
  wait                = false

  values = [
    <<-EOT
    nodeSelector:
      karpenter.sh/controller: 'true'
    tolerations:
      - key: CriticalAddonsOnly
        operator: Exists
      - key: karpenter.sh/controller
        operator: Exists
        effect: NoSchedule
    webhook:
      enabled: false
    #  port: 8443
    settings:
      clusterName: ${module.eks.cluster_name}
      clusterEndpoint: ${module.eks.cluster_endpoint}
      interruptionQueue: ${module.karpenter.queue_name}
    EOT
  ]

  #lifecycle {
  #  ignore_changes = [
  #    repository_password
  #  ]
  #}
}

################################################################################
# EKS Blueprints Addons
################################################################################

module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.14"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  enable_metrics_server = true
  enable_cert_manager   = true
  enable_aws_load_balancer_controller = true
  aws_load_balancer_controller = {
    set = [
      {
        name  = "replicaCount"
        value = 2
      },
      {
        name  = "vpcId"
        value = var.vpc_id
      },
      {
        name  = "image.tag"
        value = var.aws_lb_controller
      },
      {
        name  = "podDisruptionBudget.maxUnavailable"
        value = 1
      },
      {
        name  = "enableServiceMutatorWebhook"
        value = "false"
      }
    ]
  }
  #enable_bottlerocket_update_operator = true

  #enable_aws_efs_csi_driver = true
  #aws_efs_csi_driver = {
  #  repository     = "https://kubernetes-sigs.github.io/aws-efs-csi-driver/"
  #  chart_version  = "2.5.6"
  #}
}
