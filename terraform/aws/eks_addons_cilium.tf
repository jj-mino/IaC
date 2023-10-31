## there is not a 'kubernetes_daemonset' datasource to do be used for the trigger
## and is required due EKS comes with its own CNI by default (https://github.com/aws/containers-roadmap/issues/71)
resource "null_resource" "remove-aws-vpc-cni" {
  triggers = {}
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      KUBECONFIG = nonsensitive(base64encode(local.kubeconfig)) # value is not shown at the output as it's provided as a var
    }
    command = <<-EOT
      kubectl delete daemonset aws-node --namespace kube-system --ignore-not-found --kubeconfig <(echo $KUBECONFIG | base64 -d)
    EOT
  }
  depends_on = [
    module.eks.eks_managed_node_groups # do not delete the cni until the default nodegroup where cilium will be installed is ready
  ]
}

# install cilium cni after removing the built-in aws cni
resource "helm_release" "cilium" {
  name       = "cilium"
  repository = "https://helm.cilium.io/"
  chart      = "cilium"
  namespace  = "kube-system"
  version    = "1.14.1"
  values = [
    <<-EOT
    eni:
      enabled: true
    cni:
      chainingMode: "none"
    enableIPv4Masquerade: false
    tunnel: disabled
    endpointRoutes:
      enabled: true
    ipam:
      mode: eni
    egressMasqueradeInterfaces: eth0
    tunnel: disabled
    nodeinit: 
      enabled: true
    hubble:
      enabled: true
      listenAddress: ":4244"
      relay:
        enabled: true
      ui: 
        enabled: true
      metrics:
        enabled: 
          - dns
          - drop
          - tcp
          - flow
          - icmp
          - http
          - policy:sourceContext=app|workload-name|pod|reserved-identity;destinationContext=app|workload-name|pod|dns|reserved-identity;labelsContext=source_namespace,destination_namespace
        enableOpenMetrics: true
    prometheus:
      enabled: true
    operator:
      prometheus:
        enabled: true
    logOptions:
      level: "error"
    EOT
  ]
  depends_on = [
    null_resource.remove-aws-vpc-cni
  ]
}