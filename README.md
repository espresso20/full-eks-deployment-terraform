# Full EKS Dev Stack — Terraform

A complete, budget-conscious AWS EKS development cluster built with Terraform. Designed for rapid spin-up and teardown when demoing or testing small containerised applications. Includes VPC, networking, IAM, EKS control plane, managed node group, ECR, VPC endpoints, and Kubernetes manifests for a sample app.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  VPC  10.0.0.0/16  (us-east-1)                                  │
│                                                                  │
│  ┌──────────────────────┐   ┌──────────────────────┐            │
│  │  Public Subnet AZ-a  │   │  Public Subnet AZ-b  │            │
│  │  10.0.1.0/24         │   │  10.0.2.0/24         │            │
│  │  [NAT GW]  [NLB]     │   │  [NLB]               │            │
│  └──────────────────────┘   └──────────────────────┘            │
│                                                                  │
│  ┌──────────────────────┐   ┌──────────────────────┐            │
│  │  Private Subnet AZ-a │   │  Private Subnet AZ-b │            │
│  │  10.0.10.0/24        │   │  10.0.11.0/24        │            │
│  │  [EKS Node]          │   │  [EKS Node]          │            │
│  └──────────────────────┘   └──────────────────────┘            │
│                                                                  │
│  VPC Endpoints: ecr.api · ecr.dkr · s3 · sts · ec2              │
└─────────────────────────────────────────────────────────────────┘
                          │
                   EKS Control Plane
                   (AWS managed)
```

**Nodes** sit in private subnets with no public IPs. They reach ECR and AWS APIs through VPC PrivateLink endpoints — not via the NAT gateway — which also avoids NAT data-processing costs on image pulls.

**Load balancers** (NLB) are provisioned in public subnets automatically by the Kubernetes `LoadBalancer` service type.

---

## What's Included

| Layer | Resources |
|---|---|
| **Networking** | VPC, public/private subnets (2 AZs), IGW, single NAT gateway, route tables |
| **VPC Endpoints** | ecr.api, ecr.dkr (interface), s3 (gateway), sts, ec2 (interface) |
| **EKS** | Control plane (Kubernetes 1.31), managed node group (t3.medium × 2) |
| **IAM** | Cluster role, node role (ECR + SSM), EBS CSI IRSA role |
| **Add-ons** | vpc-cni, coredns, kube-proxy, aws-ebs-csi-driver |
| **ECR** | Private repository for app images, lifecycle policy (keep last 5) |
| **App** | `hello-server` Deployment + NLB Service in `k8s/hello-server/` |

---

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.6
- [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Docker](https://docs.docker.com/get-docker/) with `buildx` support
- An AWS SSO profile configured in `~/.aws/config`

---

## Quick Start

`terraform.tfvars` is the only file you need to edit. All scripts read their config from `terraform output` at runtime — no values are hardcoded anywhere else.

### 1. Configure terraform.tfvars

```hcl
aws_region  = "us-east-1"
aws_profile = "your-sso-profile-name"  # your AWS SSO profile

cluster_name    = "dev-eks"
cluster_version = "1.31"
...
```

Log in to AWS SSO before running any commands:

```bash
aws sso login --profile your-sso-profile-name
```

### 2. Initialise Terraform

```bash
terraform init
```

### 3. Deploy the stack

```bash
terraform apply -var-file="terraform.tfvars"
```

Takes ~12–15 minutes. The EKS cluster and node group are the slow parts. When complete, kubectl is configured automatically by the deploy script.

### 4. Deploy an application

Build your image for `linux/amd64` (required — nodes are x86_64):

```bash
docker buildx build --platform linux/amd64 -t hello-server:latest .
```

Push to ECR and deploy to the cluster:

```bash
./push-and-deploy.sh                        # uses hello-server:latest
./push-and-deploy.sh myimage:tag v2.0       # custom image + ECR tag
```

The script reads your profile, region, cluster name, and ECR URL from `terraform output` — then authenticates Docker, pushes the image, applies the Kubernetes manifests, and waits for the rollout.

---

## Teardown

```bash
./teardown.sh
```

Type `destroy` when prompted. The script:

1. Deletes all Kubernetes `LoadBalancer` services (which removes the AWS NLBs)
2. Waits for AWS to fully release the NLB ENIs from the VPC
3. Deletes PersistentVolumeClaims (releases EBS volumes)
4. Runs `terraform destroy`

> Skipping step 1 and running `terraform destroy` directly will cause it to hang on VPC deletion because AWS still has ENIs attached from the load balancer.

To rebuild from scratch after a teardown:

```bash
terraform apply -var-file="terraform.tfvars"
aws eks update-kubeconfig --region us-east-1 --name dev-eks --profile your-sso-profile-name
./push-and-deploy.sh
```

---

## Configuration

All tuneable values live in `terraform.tfvars`:

| Variable | Default | Description |
|---|---|---|
| `aws_region` | `us-east-1` | AWS region |
| `aws_profile` | `sso-profile` | AWS CLI SSO profile name |
| `cluster_name` | `dev-eks` | Cluster name and resource prefix |
| `cluster_version` | `1.31` | Kubernetes version |
| `vpc_cidr` | `10.0.0.0/16` | VPC CIDR block |
| `node_instance_type` | `t3.medium` | Worker node EC2 type |
| `node_min_size` | `1` | Minimum nodes |
| `node_max_size` | `3` | Maximum nodes |
| `node_desired_size` | `2` | Nodes at launch |
| `node_disk_size` | `20` | Node root volume (GiB) |

---

## State Backend

Defaults to S3 remote state (see `backend.tf`). The bucket and key are already configured. To use a different bucket, update `backend.tf` and re-initialise:

```bash
terraform init -reconfigure
```

---

## Accessing Nodes

Nodes have no SSH key and no public IP. Use SSM Session Manager:

```bash
# Find an instance ID
aws ec2 describe-instances \
  --filters "Name=tag:eks:cluster-name,Values=dev-eks" \
  --query "Reservations[*].Instances[*].InstanceId" \
  --profile your-sso-profile-name

aws ssm start-session --target <instance-id> --profile your-sso-profile-name
```

---

## Adding More Applications

1. Add a directory under `k8s/<app-name>/` with `deployment.yaml` and `service.yaml`
2. Use the ECR repo URL from the `ecr_repository_url` Terraform output as the image prefix
3. Build with `--platform linux/amd64` and push via `push-and-deploy.sh` (or adapt the script)

To add a new ECR repository, add an `aws_ecr_repository` resource to `ecr.tf` following the existing pattern.

---

## Approximate Monthly Cost (dev usage)

| Resource | Est. Cost |
|---|---|
| EKS control plane | $73 |
| 2× t3.medium nodes | $60 |
| NAT gateway (single) | $32 |
| VPC interface endpoints (4×) | $29 |
| NLB | $16 |
| EBS (2× 20 GiB gp2) | $4 |
| ECR storage | <$1 |
| **Total** | **~$215/month** |

> Tear down when not in use — the cluster can be fully destroyed and rebuilt in under 20 minutes.
