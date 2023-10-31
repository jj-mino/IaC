module "iam_role_for_service_accounts_eks_ebs" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"

  create_role           = true
  role_name             = "ebs-csi-${lower(terraform.workspace)}-role"
  attach_ebs_csi_policy = true

  oidc_providers = {
    one = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}

resource "helm_release" "aws-ebs-csi-driver" {
  name             = "ebs-csi"
  repository       = "https://kubernetes-sigs.github.io/aws-ebs-csi-driver"
  chart            = "aws-ebs-csi-driver"
  namespace        = "kube-system"
  version          = "2.23.0"
  create_namespace = true
  reuse_values     = true
  wait             = true
  recreate_pods    = true
  atomic           = true
  cleanup_on_fail  = true

  values = [
    templatefile("${path.module}/templates/ebs/helm_ebs_values.yaml", {
      aws_region   = data.aws_region.current.name
      cluster_name = module.eks.cluster_name
      k8s_sa_name  = "ebs-csi-controller-sa"
      iam_role_arn = module.iam_role_for_service_accounts_eks_ebs.iam_role_arn
    })
  ]
}
