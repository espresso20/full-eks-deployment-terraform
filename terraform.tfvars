aws_region  = "us-east-1"
aws_profile = "sso-profile"

cluster_name    = "dev-eks"
cluster_version = "1.31"

vpc_cidr             = "10.0.0.0/16"
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]

# t3.medium: 2 vCPU / 4 GB — cheapest viable node for running system pods + a demo app
node_instance_type = "t3.medium"
node_min_size      = 1
node_max_size      = 3
node_desired_size  = 2
node_disk_size     = 20
