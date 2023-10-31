resource "aws_s3_bucket" "prometheus_thanos_aws_s3_bucket" {
  bucket = "prometheus-thanos-${lower(terraform.workspace)}"

  versioning {
    enabled = true
  }
}

resource "aws_s3_bucket_ownership_controls" "prometheus_thanos_aws_s3_bucket" {
  bucket = aws_s3_bucket.prometheus_thanos_aws_s3_bucket.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_public_access_block" "prometheus_thanos_aws_s3_bucket_public_access_block" {
  bucket                  = aws_s3_bucket.prometheus_thanos_aws_s3_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_iam_policy" "prometheus_thanos_aws_iam_policy" {
  name   = "prometheus-thanos-sa-${lower(terraform.workspace)}-policy"
  policy = <<-EOT
        {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Sid": "Statement",
                    "Effect": "Allow",
                    "Action": [
                        "s3:ListBucket",
                        "s3:GetObject",
                        "s3:DeleteObject",
                        "s3:PutObject"
                    ],
                    "Resource": [
                        "${aws_s3_bucket.prometheus_thanos_aws_s3_bucket.arn}/*",
                        "${aws_s3_bucket.prometheus_thanos_aws_s3_bucket.arn}"
                    ]
                }
            ]
        }
    EOT
}

module "iam_role_for_service_accounts_eks" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"

  create_role = true
  role_name   = "prometheus-thanos-sa-${lower(terraform.workspace)}-role"

  role_policy_arns = {
    additional = aws_iam_policy.prometheus_thanos_aws_iam_policy.arn
  }

  oidc_providers = {
    one = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["observability:prometheus-thanos-sa-${lower(terraform.workspace)}"]
    }
  }
}

# https://thanos.io/tip/thanos/storage.md/#s3
resource "kubernetes_secret" "prometheus_thanos_secret" {
  metadata {
    name      = "thanos-storage-config"
    namespace = "observability"
  }

  data = {
    "thanos-storage-config.yaml" = <<-EOT
        type: s3
        config:
          bucket: "prometheus-thanos-${lower(terraform.workspace)}"
          endpoint: "s3.us-west-2.amazonaws.com"
          trace:
            enable: true
    EOT
  }

  type = "Opaque"
}

resource "helm_release" "prometheus_stack" {
  name             = "prometheus"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  namespace        = "observability"
  version          = "51.0.0"
  create_namespace = true
  reuse_values     = true
  wait             = true
  recreate_pods    = true
  atomic           = true
  cleanup_on_fail  = true

  values = [
    templatefile(
      "${path.module}/templates/prometheus/helm_prometheus_stack.yaml",
      {
        serviceAccount            = "prometheus-thanos-sa-${lower(terraform.workspace)}",
        serviceAccountAnnotations = module.iam_role_for_service_accounts_eks.iam_role_arn
      }
    )
  ]

  depends_on = [
    kubernetes_secret.prometheus_thanos_secret
  ]
}

resource "helm_release" "prometheus_adapter" {
  name             = "adapter"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "prometheus-adapter"
  namespace        = "observability"
  version          = "4.4.1"
  create_namespace = true
  reuse_values     = true
  wait             = true
  recreate_pods    = true
  atomic           = true
  cleanup_on_fail  = true

  values = [file("${path.module}/templates/prometheus/helm_prometheus_adapter_values.yaml")]

  depends_on = [
    helm_release.prometheus_stack
  ]
}

resource "helm_release" "thanos" {
  name             = "thanos"
  chart            = "oci://registry-1.docker.io/bitnamicharts/thanos"
  namespace        = "observability"
  version          = "12.13.3"
  create_namespace = true
  reuse_values     = true
  wait             = true
  recreate_pods    = true
  atomic           = true
  cleanup_on_fail  = true

  values = [
    templatefile(
      "${path.module}/templates/prometheus/helm_thanos.yaml",
      {
        s3Bucket               = "prometheus-thanos-${lower(terraform.workspace)}",
        existingServiceAccount = "prometheus-thanos-sa-${lower(terraform.workspace)}"
      }
    )
  ]

  depends_on = [
    helm_release.prometheus_stack
  ]
}
