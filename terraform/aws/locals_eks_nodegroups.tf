locals {
  default_ami_id_linux = var.nodegroup_ami_id != "" ? var.nodegroup_ami_id : concat(data.aws_ami.eks_worker.*.id, [""])[0]
  managed_nodegroups_instance_types = {
    default        = "c5.2xlarge"
  }

  managed_nodegroups_taints = [{ key = "node.cilium.io/agent-not-ready", value = "true", effect = "NO_EXECUTE" }]

  managed_nodegroups_config = {
    max_size                   = 450
    min_size                   = 0 # so cluster-austoscaler can scale it 
    desired_size               = 0
    ami_type                   = "CUSTOM"
    capacity_type              = "ON_DEMAND"
    use_custom_launch_template = true
    block_device_mappings = {
      xvda = {
        device_name = "/dev/xvda"
        ebs = {
          volume_size           = 100
          volume_type           = "gp3"
          delete_on_termination = true
          encrypted             = true
        }
      }
    }
    create_launch_template     = true # so they can be tied to an ami
    launch_template_os         = "amazonlinux2eks"
    enable_monitoring          = true
    subnet_ids                 = local.vpc_private_subnets_ids
    instance_types             = local.managed_nodegroups_instance_types["default"]
    update_config              = { max_unavailable_percentage = 15 }
    taints                     = local.managed_nodegroups_taints
    post_bootstrap_user_data   = <<-EOT
    # install ethtool to get ENA metrics # testing
    yum install ethtool -y
    EOT
    ami_id                     = local.default_ami_id_linux
    enable_bootstrap_user_data = true
    bootstrap_extra_args       = "--cluster-dns ${local.node_local_dns_ip}\",\"${local.dns_cluster_ip}"
    force_update_version       = true
    iam_role_additional_policies = {
      additional = aws_iam_policy.efs.arn
    }
  }

  /* ------------------------------ nodegroups to be created ------------------------------ */
  managed_node_groups = {
    default = merge(local.managed_nodegroups_config, {
      node_group_name      = "default"
      launch_template_name = "default"
      desired_size         = 1 # for helm charts to be installed
      min_size             = 1
      labels               = { stack = "default" }
      tags                 = merge(local.tags, { Type = "workers-nodes", Stack = "platform", Nodegroup = "default" })
    })
  })

}