
locals {
  /* ------------------------------ EKS CONFIG ------------------------------ */
  kube_proxy_patch_command = "kubectl patch daemonset kube-proxy -n kube-system --type='json' -p='[{\"op\": \"replace\", \"path\": \"/spec/template/spec/containers/0/command/1\", \"value\": \"--v=0\" }]'" # default is "2"

  kubeconfig = yamlencode({
    apiVersion      = "v1"
    kind            = "Config"
    current-context = "terraform"
    clusters = [{
      name = module.eks.cluster_name
      cluster = {
        certificate-authority-data = module.eks.cluster_certificate_authority_data
        server                     = module.eks.cluster_endpoint
      }
    }]
    contexts = [{
      name = "terraform"
      context = {
        cluster = module.eks.cluster_name
        user    = "terraform"
      }
    }]
    users = [{
      name = "terraform"
      user = {
        token = data.aws_eks_cluster_auth.this.token
      }
    }]
  })

  node_local_dns_ip = "169.254.20.10"
  dns_cluster_ip    = "172.20.0.10"

  /* ------------------------------ EKS External DNS config ------------------------------ */
  dns_hosted_zone_name = "myawesomedomain.com"

  /* ------------------------------ RESOURCES TAGS ------------------------------ */
  tags = {
    Owner       = "mycompany"
    Workspace   = terraform.workspace
  }

  secrets_recovery_window_in_days = 30
}
