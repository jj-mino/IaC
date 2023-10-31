locals {
  grafana_dashboards = fileset("${path.module}/templates/grafana-dashboards", "**/*.json")
  grafana_alerts     = fileset("${path.module}/templates/grafana-alerts", "**/*.yaml")
  grafana_hostname   = "grafana-${terraform.workspace}.${local.dns_hosted_zone_name}"
  handle_critical_severity_as = teraform.workspace == "dev" ? "warning" : "critical"
}

/* ------------------------------ EKS OBSERVABILITY NAMESPACE  ------------------------------ */
resource "kubernetes_namespace" "observability" {
  metadata {
    name = "observability"
  }
  depends_on = [
    module.eks
  ]
}

/* ------------------------------ EKS DOCKERHUB CREDENTIALS ------------------------------ */
resource "kubernetes_secret" "docker_hub" {
  for_each = toset([kubernetes_namespace.observability.metadata.0.name, "kube-system"])
  metadata {
    name      = "dockerhub-auth"
    namespace = each.key
  }
  type = "kubernetes.io/dockerconfigjson"
  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        "https://index.docker.io/v1/" = {
          "username" = local.docker_hub_username
          "password" = local.docker_hub_password
          "email"    = local.docker_hub_email
          "auth"     = base64encode("${local.docker_hub_username}:${local.docker_hub_password}")
        }
      }
    })
  }
  depends_on = [
    kubernetes_namespace.observability
  ]
}

/* ------------------------------ GRAFANA CONFIG ------------------------------- */
resource "kubectl_manifest" "grafana_dashboards" {
  for_each   = { for i, k in local.grafana_dashboards : k => i }
  yaml_body  = <<EOT
    apiVersion: v1
    kind: ConfigMap
    metadata:
      annotations:
        grafana_folder: "./${lower(dirname(each.key))}"
      labels:
        grafana_dashboard: "true"
        app.kubernetes.io/name: grafana
      name: grafana-alerting-${lower(trim(basename(each.key), ".json"))}
      namespace: ${kubernetes_namespace.observability.metadata.0.name}
    data:
      ${lower(basename(each.key))}: |-
        ${indent(8, file("${path.module}/templates/grafana-dashboards/${each.key}"))}
    EOT
  depends_on = [module.eks]
}

resource "kubectl_manifest" "grafana_alerts_rules" {
  for_each = { for i, k in local.grafana_alerts : k => i }
  yaml_body = <<EOT
    apiVersion: v1
    kind: ConfigMap
    metadata:
      labels:
        grafana_alert: "true"
        app.kubernetes.io/name: grafana
      name: grafana-alert-${lower(trim(basename(each.key), ".yaml"))}
      namespace: ${kubernetes_namespace.observability.metadata.0.name}
    data:
      ${lower(basename(each.key))}: |-
        ${indent(8, templatefile("${path.module}/templates/grafana-alerts/${each.key}", {
          env_code = terraform.workspace
          handle_critical_severity_as = local.handle_critical_severity_as
        }))}
    EOT
depends_on = [module.eks]
}

resource "kubectl_manifest" "grafana_alerts_notifications_templates" {
  yaml_body  = <<EOT
    apiVersion: v1
    kind: ConfigMap
    metadata:
      labels:
        grafana_alert: "true"
        app.kubernetes.io/name: grafana
      name: grafana-alert-template
      namespace: ${kubernetes_namespace.observability.metadata.0.name}
    data:
      alert-template.yaml: |-
        apiVersion: 1
        templates:
          - orgID: 1
            name: slack.
            template: |-
              {{ define "alert_severity_prefix_emoji" -}}
                {{- if ne .Status "firing" -}}
                  :white_check_mark:
                {{- else if eq .CommonLabels.severity "critical" -}}
                  :red_circle:
                {{- else if eq .CommonLabels.severity "warning" -}}
                  :warning:
                {{- end -}}
              {{- end -}}
              {{ define "slack.title" -}}
                {{ template "alert_severity_prefix_emoji" . }} {{ .CommonLabels.env_code }} |  {{ .CommonLabels.alertname }} [x{{ .Alerts.Firing | len -}}]
              {{- end -}}
          - orgID: 1
            name: message
            template: |-
              {{ define "message" -}}
              {{- range .Alerts -}}
              {{ .Annotations.summary}}
              {{ end }}
              {{- end -}}
    EOT
  depends_on = [module.eks]
}

resource "kubectl_manifest" "grafana_alerts_notifications" {
  yaml_body  = <<EOT
    apiVersion: v1
    kind: ConfigMap
    metadata:
      labels:
        grafana_alert: "true"
        app.kubernetes.io/name: grafana
      name: grafana-alert-slack-contactpoint
      namespace: ${kubernetes_namespace.observability.metadata.0.name}
    data:
      slack-notifications.yaml: |-
        apiVersion: 1

        contactPoints:
          - orgId: 1
            name: slack-notification
            receivers:
            - uid: slack-notification
              type: slack
              settings:
                url: ${data.aws_secretsmanager_secret_version.secret_version["grafana_slack_webhook"].secret_string}
                title: |-
                  {{ template "slack.title" . }}
                text: |-
                  {{ template "message" . }}
              disableResolveMessage: true

          - orgId: 1
            name: opsgenie-notification
            receivers:
            - uid: opsgenie-notification
              type: opsgenie
              settings:
                apiKey: ${data.aws_secretsmanager_secret_version.secret_version["grafana_opsgenie_apikey"].secret_string}
                apiUrl: https://api.opsgenie.com/v2/alerts
                message: |
                  {{ .CommonLabels.env_code }} |  {{ .CommonLabels.alertname }} [x{{ .Alerts.Firing | len -}}]
                description: |
                  {{ template "message" . }} 
                  tags: {grafana, platform, ${lower(var.deployment_type)}, s0}
                autoClose: false
                overridePriority: false
                sendTagsAs: both

        policies:
          - orgId: 1
            receiver: grafana-default-email
            group_by: ['alertname']
            routes:
            - receiver: slack-notification
              group_wait: 30s
              group_interval: 2m
              repeat_interval: 30m
              matchers:
                - severity = "warning"
              continue: false

            - receiver: opsgenie-notification
              group_wait: 30s
              group_interval: 2m
              repeat_interval: 30m
              matchers:
                - severity = "critical"
              continue: false
    EOT
  depends_on = [module.eks]
}

/* ------------------------------ GRAFANA DEPLOYMENT ------------------------------- */
resource "kubectl_manifest" "external_secrets_store" {
  yaml_body = <<EOT
    apiVersion: external-secrets.io/v1alpha1
    kind: ClusterSecretStore
    metadata:
      name: cluster-secret-store
      namespace: ${module.eks_kubernetes_addons.external_secrets.namespace}
    spec:
      provider:
        aws:
          service: SecretsManager
          region: ${var.aws_region}
          auth:
            jwt:
              serviceAccountRef:
                namespace: ${module.eks_kubernetes_addons.external_secrets.namespace}
                name: ${local.external_secrets_service_account_name}
    EOT
}

resource "kubectl_manifest" "grafana_google_client" {
  yaml_body = <<EOT
    apiVersion: external-secrets.io/v1alpha1
    kind: ExternalSecret
    metadata:
      name: grafana-google-client
      namespace: ${kubernetes_namespace.observability.metadata.0.name}
    spec:
      refreshInterval: 1m
      secretStoreRef:
        name: ${kubectl_manifest.external_secrets_store.name}
        kind: ClusterSecretStore
      target:
        name: grafana-google-client
      data:
        - secretKey: GF_AUTH_GOOGLE_CLIENT_ID
          remoteRef:
            key: ${data.aws_secretsmanager_secret.secret["grafana_google_client_id"].name}
        - secretKey: GF_AUTH_GOOGLE_CLIENT_SECRET
          remoteRef:
            key: ${data.aws_secretsmanager_secret.secret["grafana_google_client_secret"].name}
    EOT
}

resource "helm_release" "grafana" {
  name          = "grafana"
  repository    = "https://grafana.github.io/helm-charts"
  chart         = "grafana"
  namespace     = kubernetes_namespace.observability.metadata.0.name
  wait          = true
  recreate_pods = true
  atomic        = true
  version       = "6.55.1"
  values = [
    templatefile(
      "${path.module}/templates/grafana/grafana-values.yaml",
      {
        host                             = "grafana-${terraform.workspace}.${local.dns_hosted_zone_name}"
        certificate-arn                  = data.aws_acm_certificate.myawesomedomain.arn
        ingress-class                    = "internet-facing"
        workspace                        = terraform.workspace
        google-client-creds-secret       = "grafana-google-client"
        grafana_unified_alerting_enabled = var.grafana_unified_alerting_enabled
      }
    )
  ]

  ## Patch ingress to remove finalizers that prevents it to be removed
  # provisioner "local-exec" {
  #   when = "destroy"
  #   inline = [
  #     "kubectl patch ingress grafana -n ${kubernetes_namespace.observability.metadata.0.name} -p ' {"metadata": {"finalizers": []}}' --type=merge"
  #   ]
  # }
  depends_on = [
    kubectl_manifest.grafana_google_client,
    kubectl_manifest.grafana_dashboards,
    kubectl_manifest.grafana_alerts_rules,
    kubectl_manifest.grafana_alerts_notifications_templates,
    kubectl_manifest.grafana_alerts_notifications,
    module.eks_kubernetes_addons # ensures that helm chart is installed after load balancer controller, so during the removal it's deleted first
  ]
}
