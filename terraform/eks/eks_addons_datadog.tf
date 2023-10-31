locals {
  datadog_namespace           = "datadog"
  datadog_api_key_secret_name = "DD_API_KEY"
  datadog_app_key_secret_name = "DD_APP_KEY"
}

/* ------------------------------ DATADOG ------------------------------ */
data "kubectl_file_documents" "datadog" {
  count   = var.datadog_enabled ? 1 : 0
  content = <<-EOT
    apiVersion: 'external-secrets.io/v1alpha1'
    kind: ExternalSecret
    metadata:
      name: "datadog-external-secret"
      namespace: ${local.datadog_namespace}
      annotations:
        meta.helm.sh/release-name: datadog
        meta.helm.sh/release-namespace: ${local.datadog_namespace}
      labels:
        app.kubernetes.io/instance: datadog
        app.kubernetes.io/managed-by: Helm
        app.kubernetes.io/name: datadog
    spec:
      refreshInterval: 1m
      secretStoreRef:
        name: cluster-secret-store
        kind: ClusterSecretStore
      target:
        name: "datadog-external-secret"
      data:
        - secretKey: api-key 
          remoteRef:
            key: ${data.aws_secretsmanager_secret.secret["datadog_api_key"].name}
        - secretKey: app-key
          remoteRef:
            key: ${data.aws_secretsmanager_secret.secret["datadog_app_key"].name}
  EOT
}

resource "kubectl_manifest" "datadog" {
  count      = var.datadog_enabled ? length(data.kubectl_file_documents.datadog[0].documents) : 0
  yaml_body  = element(data.kubectl_file_documents.datadog[0].documents, count.index)
  depends_on = [local.kubeconfig]
}


resource "helm_release" "datadog" {
  count            = var.datadog_enabled ? 1 : 0
  repository       = "https://helm.datadoghq.com"
  chart            = "datadog"
  version          = "3.28.1"
  name             = "datadog"
  namespace        = local.datadog_namespace
  create_namespace = true
  wait             = true
  timeout          = 600
  values = [
    templatefile("${path.module}/templates/datadog-values/common.yaml", {
      CLUSTER_NAME = local.eks_cluster_name,
      ENV          = lower(terraform.workspace),
      APP_ENV      = upper(terraform.workspace)
    }),
    templatefile("${path.module}/templates/datadog-values/${terraform.workspace}.yaml", {
      APP_ENV  = upper(terraform.workspace)
    })
  ]
  depends_on = [
    kubectl_manifest.datadog
  ]
}