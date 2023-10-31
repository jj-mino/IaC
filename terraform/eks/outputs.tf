/* ------------------------------ MISC  ------------------------------ */
output "applied_on" {
  value       = timestamp()
  description = "UTC timestamp when terraform plan was applied"
}

output "terraform_workspace" {
  value = terraform.workspace
}

/* ------------------------------ GIT OUTPUTS  ------------------------------ */
output "git_tag" {
  value = data.git_repository.current.tag
}

output "git_branch" {
  value = data.git_repository.current.branch
}
output "git_commit_sha" {
  value = data.git_repository.current.commit_sha
}

/* ------------------------------ AWS OUTPUTS  ------------------------------ */
output "account_id" {
  value = data.aws_caller_identity.current.account_id
}

output "caller_arn" {
  value = data.aws_caller_identity.current.arn
}

output "aws_region" {
  value = var.aws_region
}

/* ------------------------------ EKS OUTPUTS ------------------------------ */
output "eks_cluster_name" {
  value = local.eks_cluster_name
}
output "eks_nodegroups_ami" {
  value = local.default_ami_id_linux
}
