locals {
  eks_addons_common = {
    "coredns" : {
      "addon_version" : "v1.10.1-eksbuild.4"
    }
    "aws-efs-csi-driver" : {
      "addon_version" : "v1.6.0-eksbuild.1"
    }
    ## Disabled temporarily until review
    # "kubecost_kubecost": { # requires version
    #   "addon_version": "v1.103.3-eksbuild.0"
    # }
  }
  eks_addons = merge(local.eks_addons_common, { # addons dependent on cluster version
    "1.28" = {
      "kube-proxy" : {
        "addon_version" : "v1.28.1-eksbuild.1"
      }
    }
  }[module.eks.cluster_version])

  external_secrets_service_account_name = "external-secrets-sa"

  # helm charts that will be installed all together by the TF addons module
  helm_releases = {
    external-dns = {
      description      = "External dns controller that updates cloudflare entries"
      namespace        = "kube-system"
      create_namespace = true
      chart            = "external-dns"
      chart_version    = "6.18.0"
      repository       = "https://charts.bitnami.com/bitnami"
      wait             = true
      values = [
        <<-EOT
          provider: cloudflare
          txtOwnerId: ${local.eks_cluster_name}
          domainFilters:
            - ${local.dns_hosted_zone_name}
          cloudflare-proxied: false
          policy: upsert-only # only adds entries, while "sync" would removes DNS record if ingress is deleted
          cloudflare:
            secretName: ${kubernetes_secret.cf_api_token.metadata.0.name}
        EOT
      ]
    }
    # keda = {  # Conflicts with DD (https://github.com/kedacore/keda/issues/470#issuecomment-696977212)
    #   namespace        = "keda"
    #   create_namespace = true
    #   chart            = "keda"
    #   chart_version    = "2.11.2"
    #   repository       = "https://kedacore.github.io/charts"
    #   wait             = true
    #   # https://github.com/kedacore/charts/tree/main/keda
    #   values = [ ]
    # }
  }
}

# install remaining addons once cni was restored
module "eks_kubernetes_addons" {
  source            = "aws-ia/eks-blueprints-addons/aws"
  version           = "~> 1.9.1"
  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  eks_addons = local.eks_addons

  # enable_vpa = true # disable temporarily until verbosity is disabled/reduced
  # vpa = {
  #   version = "2.5.1"
  #   values = [
  #     <<-EOT
  #     recommender:
  #       extraArgs:
  #         prometheus-address: http://prometheus-server.observability.svc.cluster.local
  #         storage: prometheus
  #     EOT
  #   ]
  #   wait   = false # don't block the install
  #   atomic = false
  # }

  enable_aws_load_balancer_controller = true

  enable_metrics_server = true
  metrics_server = {
    version = "3.11.0"
  }

  enable_external_secrets = true
  external_secrets = {
    version = "0.9.4"
    values = [
      <<-EOT
      extraArgs:
        loglevel: "error"
      EOT
    ]
    service_account_name = local.external_secrets_service_account_name
  }

  enable_cluster_autoscaler = true
  cluster_autoscaler = {
    version = "9.29.3"
    values = [
      <<-EOT
      autoDiscovery:
        clusterName: ${local.eks_cluster_name}
      extraArgs:
        logtostderr: true
        stderrthreshold: 2 # ERROR
        v: "0"
      awsRegion: ${var.aws_region}
      EOT
    ]
  }

  enable_cluster_proportional_autoscaler = true
  cluster_proportional_autoscaler = {
    # for coredns
    version = "1.8.9"
    values = [
      <<-EOT
      config:
        linear:
          coresPerReplica: 256
          nodesPerReplica: 16
          preventSinglePointFailure: true
          includeUnschedulableNodes: true
      options:
        target: deployment/coredns # Notice the target as `deployment/coredns`
      serviceAccount:
        create: true
        name: kube-dns-autoscaler
      tolerations:
        - key: "CriticalAddonsOnly"
          operator: "Exists"
          description: "Cluster Proportional Autoscaler for CoreDNS Service"
      EOT
    ]
  }



  helm_releases = local.helm_releases

  depends_on = [
    helm_release.cilium
  ]
}

# /* ------------------------------ EKS BLUEPRINT ADDONS ------------------------------ */
# module "eks_kubernetes_addons_old" {
#   source                            = "github.com/aws-ia/terraform-aws-eks-blueprints//modules/kubernetes-addons?ref=v4.32.1"
#   eks_cluster_id                    = module.eks.eks_cluster_id

#   /* ------------------------------ DISABLED EKS ADDONS ON PURPOSE ------------------------------ */
#   # enable_karpenter = true # to be tested as config is different (uses Karpenter provisioners instead of nodegroups)
#   # karpenter_helm_config = {
#   #   version    = "v0.27.0"
#   #   set_values = [
#   #     {
#   #       name  = "hostNetwork"
#   #       value = "true"
#   #     }
#   #   ]
#   # }
# }


/* ------------------------------ EKS EXTERNAL DNS HELM INSTALL  ------------------------------ */
resource "kubernetes_secret" "cf_api_token" {
  metadata {
    name      = "external-dns"
    namespace = "kube-system"
  }
  data = {
    cloudflare_api_token = data.aws_secretsmanager_secret_version.secret_version["cloudflare_api_token"].secret_string
  }
  type = "Opaque"
  depends_on = [
    module.eks
  ]
}


/* ------------------------------ EKS LOCAL DNS CACHE ------------------------------ */
data "kubectl_path_documents" "node_local_dns_cache" {
  pattern = "${path.module}/templates/nodelocaldns/nodelocaldns.yaml"
}

resource "kubectl_manifest" "node_local_dns_cache" {
  # https://github.com/gavinbunney/terraform-provider-kubectl/issues/52
  count     = length(data.kubectl_path_documents.node_local_dns_cache.documents)
  yaml_body = element(data.kubectl_path_documents.node_local_dns_cache.documents, count.index)
  depends_on = [
    module.eks
  ]
}


/* ------------------------------ EKS NETWORK POLICIES ------------------------------ */
resource "kubernetes_network_policy" "namespaced-default-policies" {
  for_each = var.namespaced_network_policies_enabled ? toset(concat(local.k8s_app_namespaces, ["default"])) : []
  metadata {
    name      = "${each.value}-ns-policy"
    namespace = each.value
  }
  spec {
    pod_selector {}
    policy_types = ["Ingress"]
  }
  depends_on = [
    module.k8s
  ]
}




/* ------------------------------ KUBE-PROXY PATCH ------------------------------ */
# there is not a data daemonset resource to enforce it if it's changed outside TF
resource "null_resource" "kube-proxy-logging" {
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      KUBECONFIG = nonsensitive(base64encode(local.kubeconfig)) # value is not shown at the output as it's provided as a var
    }
    command = <<-EOT
      ${local.kube_proxy_patch_command} --kubeconfig <(echo $KUBECONFIG | base64 -d) && kubectl rollout restart daemonset kube-proxy -n kube-system --kubeconfig <(echo $KUBECONFIG | base64 -d)
    EOT
  }
  triggers = {
    content = local.kube_proxy_patch_command
  }
  depends_on = [
    module.eks_kubernetes_addons
  ]
}
