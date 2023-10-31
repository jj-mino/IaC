locals {
  eks_cluster_name = "aws-${var.aws_region}-${terraform.workspace}"
}

module "eks" {
  source                         = "terraform-aws-modules/eks/aws"
  version                        = "~> 19.16"
  cluster_name                   = local.eks_cluster_name
  cluster_version                = var.eks_cluster_version
  vpc_id                         = var.vpc_id
  subnet_ids                     = local.vpc_private_subnets_ids
  cluster_endpoint_public_access = true
  manage_aws_auth_configmap      = true
  cluster_enabled_log_types      = ["audit"]
  node_security_group_additional_rules = {
    load_balancer_controller = {
      description                   = "Allow access from control plane to webhook port of AWS load balancer controller"
      protocol                      = "all"
      from_port                     = 9443
      to_port                       = 9443
      type                          = "ingress"
      source_cluster_security_group = true
    }
    vpc = {
      description = "Allow EKS private subnet communication (node to node)"
      protocol    = "all"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      cidr_blocks = local.vpc_private_subnets_cidrs
    }
  }
  eks_managed_node_groups = local.managed_node_groups
  aws_auth_roles          = local.k8s_map_roles
  iam_role_additional_policies = {
    additional = aws_iam_policy.cloudwatchAgentLogsRetention.arn
  }
}
