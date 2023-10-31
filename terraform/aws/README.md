# Purpose

Creates an EKS cluster using AWS EKS terraform blueprints and cilium CNI to support kubernetes network policies
It uses:

- Cilium CNI to support kubernetes network policies
- Thanos and S3 for prometheus HA

# Create a new environment

Create a new './tfvars/<workspace_name>.tfvars' file with the vars values and then:

```bash
# Initialize terraform:
terraform init -backend-config=../backend-config/<config file>.hcl -reconfigure -upgrade

# Create workspace
terraform workspace new <workspace_name>
```

# Deploy/Update

```bash
# Initialize terraform:
terraform init -backend-config=../backend-config/<config file>.hcl -reconfigure -upgrade

# Select the target workspace
terraform workspace select <workspace_name>

# Review and apply the changes
terraform apply -var-file "tfvars/$(terraform workspace show).tfvars" -parallelism=20
```

## Update AMIs

Terraform will look for latest AMI available, and updates the launch_template accordingly.
Existing TF module updates the [launch template default version](https://github.com/aws-ia/terraform-aws-eks-blueprints/blob/cccf5fd0a2742b0ca01df82925d41f5c77e27d12/modules/aws-eks-managed-node-groups/managed-launch-templates.tf#LL6C1-L6C1), which forces the [nodegroup update](https://github.com/aws-ia/terraform-aws-eks-blueprints/blob/cccf5fd0a2742b0ca01df82925d41f5c77e27d12/modules/aws-eks-managed-node-groups/main.tf#L40) later on.
To avoid nodegroups to be updated pin the image to a specific ami-id version.

## Post-deployment

1. Grafana
   1. Get Grafana admin credentials
      ```bash
      kubectl get secret --namespace observability grafana -o jsonpath="{.data.admin-user}" | base64 --decode ; echo
      kubectl get secret --namespace observability grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo
      ```
   2. Setup Grafana Google app redirect url to include the ingress host (`kubectl get ingress -n observability grafana`) to setup the Google auth integration
   3. If needed, setup Grafana Teams manually (https://github.com/grafana/grafana/issues/21678) and grant permissions to each folder

# Destroy

```bash
# Initialize terraform:
terraform init -backend-config=../backend-config/<config file>.hcl -reconfigure -upgrade

# Select the target workspace
terraform workspace select <workspace_name>

# Run destroy
terraform destroy -lock=false -var-file "tfvars/$(terraform workspace show).tfvars" -refresh=false
```
