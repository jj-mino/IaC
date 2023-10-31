variable "aws_region" {
  description = "Region where resources will be deployed to"
  validation {
    condition     = contains(["us-west-2", "us-east-2"], var.aws_region)
    error_message = "Valid values for are (us-west-2 | us-east-2)."
  }
  default = "us-west-2"
}

variable "namespaced_network_policies_enabled" {
  description = "Set up a default network policies on defined namespaces"
  type        = bool
  default     = true
}

variable "nodegroup_ami_id" {
  description = "Specify a fixed ami_id to be used by nodegroups. If it's empty (default) it looks for latest one available"
  type        = string
  default     = ""
}

variable "grafana_unified_alerting_enabled" {
  description = "Enable Grafana unified alerting system (All QA alerts are sent to slack)."
  type        = bool
  default     = true
}

variable "datadog_enabled" {
  description = "Enable Datadog. To be done near the cutover"
  type        = bool
  default     = false
}

variable "eks_cluster_version" {
  type        = string
  description = "EKS cluster version"
  validation {
    condition     = contains(["1.28"], var.eks_cluster_version)
    error_message = "Valid values for eks_cluster_version are (1.28)."
  }
  default = "1.28"
}

variable "vpc_id" {
  type        = string
  description = "vpc where EKS cluster will be created"
}