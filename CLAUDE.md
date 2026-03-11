# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Purpose

Full-stack Terraform deployment of a budget-conscious AWS EKS dev cluster for demoing a small web app. Covers VPC, networking, IAM, EKS control plane, managed node group, and core add-ons.

## Auth — AWS SSO

This project uses the `aroffler-dev-admin-access` SSO profile. Before any Terraform or AWS CLI command, run:

```bash
aws sso login --profile aroffler-dev-admin-access
```

The `provider "aws"` block reads the profile from `var.aws_profile` (defaults to `aroffler-dev-admin-access`). No hardcoded credentials.

## Common Commands

```bash
# First-time setup
aws sso login --profile aroffler-dev-admin-access
terraform init

# Day-to-day
terraform fmt -recursive
terraform validate
terraform plan -var-file="terraform.tfvars"
terraform apply -var-file="terraform.tfvars"

# Configure kubectl after apply (the exact command is in the 'kubeconfig_command' output)
aws eks update-kubeconfig --region us-east-1 --name dev-eks --profile aroffler-dev-admin-access

# Tear down
terraform destroy -var-file="terraform.tfvars"
```

## Architecture

```
main.tf / variables.tf / outputs.tf / terraform.tfvars
    │
    ├── modules/vpc/       VPC, public & private subnets (2 AZs), IGW, single NAT GW, route tables
    └── modules/eks/
            main.tf        EKS cluster, OIDC provider, security groups, managed node group, add-ons, EBS CSI IRSA
            iam.tf         IAM roles — cluster role, node role (+SSM), EBS CSI driver role
```

### Key design decisions

| Decision | Rationale |
|---|---|
| Single NAT gateway | Saves ~$30/month vs one per AZ; acceptable for dev |
| Nodes in private subnets | Best practice; public endpoint still allows kubectl from internet |
| `endpoint_public_access = true` | Dev convenience — no VPN needed |
| `bootstrap_cluster_creator_admin_permissions = true` | SSO identity gets cluster admin on creation so kubectl works immediately |
| `authentication_mode = "API_AND_CONFIG_MAP"` | Supports both new Access Entries API and legacy aws-auth ConfigMap |
| No SSH key on nodes | SSM Session Manager is attached via `AmazonSSMManagedInstanceCore`; use `aws ssm start-session` |
| `ignore_changes = [scaling_config[0].desired_size]` | Allows cluster autoscaler to manage node count without Terraform drift |
| EBS CSI driver with IRSA | Required for PersistentVolume support; IRSA role scoped to `kube-system/ebs-csi-controller-sa` |

### Module wiring

VPC outputs (`vpc_id`, `private_subnet_ids`, `public_subnet_ids`) flow directly into the EKS module. The root `outputs.tf` surfaces the most useful values, including a ready-to-run `kubeconfig_command`.

### State

Defaults to local state (`backend.tf`). The commented-out S3 backend block in `backend.tf` is the migration path — fill in bucket/table names and run `terraform init -migrate-state`.

## Changing cluster version

Update `cluster_version` in `terraform.tfvars`. EKS in-place upgrades require incrementing one minor version at a time (e.g. 1.30 → 1.31 → 1.32).

## Adding IRSA roles for new add-ons

Pattern is in `modules/eks/main.tf` (see `ebs_csi_assume_role`):
1. Create `aws_iam_policy_document` with a `StringEquals` condition on `<oidc-url>:sub` matching the service account.
2. Create `aws_iam_role` using that document.
3. Attach the relevant managed or inline policy.
4. Reference `module.eks.oidc_provider_arn` from the root, or `aws_iam_openid_connect_provider.eks.arn` from within the eks module.
