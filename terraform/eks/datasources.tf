locals {
  aws_secrets = {
    docker_hub_credentials       = "DOCKER_HUB_CREDENTIALS"
    cloudflare_api_token         = "CLOUDFLARE_API_TOKEN_MYAWESOMEDOMAIN.COM"
    grafana_google_client_id     = "GRAFANA_GOOGLE_CLIENT_ID"
    grafana_google_client_secret = "GRAFANA_GOOGLE_CLIENT_SECRET"
    grafana_slack_webhook        = "GRAFANA_SLACK_WEBHOOK"
    grafana_opsgenie_apikey      = "GRAFANA_OPSGENIE_APIKEY"
  }
}




data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_partition" "current" {}

data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "git_repository" "current" {
  path = "${path.root}/../.."
}


/* ------------------------------ AWS SECRETS ------------------------------ */
data "aws_secretsmanager_secret" "secret" {
  for_each = local.aws_secrets
  name     = each.value
}
data "aws_secretsmanager_secret_version" "secret_version" {
  for_each  = local.aws_secrets
  secret_id = data.aws_secretsmanager_secret.secret[each.key].id
}




/* ------------------------------ EKS AMIs ------------------------------ */
# If the variable update_nodes_ami is TRUE means that we need look in AWS for the latest AMI available.
data "aws_ami" "eks_worker" {
  count = var.nodegroup_ami_id == "" ? 1 : 0
  filter {
    name   = "name"
    values = ["amazon-eks-node-${var.eks_cluster_version}-v*"]
  }
  most_recent = true
  owners      = ["amazon"]
}


/* ------------------------------ EKS GRAFANA ------------------------------ */
data "aws_acm_certificate" "myawesomedomain" {
  domain      = "*.mydomain.com"
  types       = ["AMAZON_ISSUED"]
  most_recent = true
}