# VPC endpoints so nodes in private subnets can reach ECR and S3
# without traversing the public internet via the NAT gateway.
#
# Required for ECR image pulls:
#   ecr.api  — authenticate and list images
#   ecr.dkr  — pull image layers (Docker protocol)
#   s3       — ECR stores actual layer blobs in S3 (Gateway endpoint, free)
#
# Also included:
#   sts      — nodes need STS to assume IAM roles (IRSA)
#   ec2      — EKS control plane uses EC2 APIs for node lifecycle

# ── Security group for interface endpoints ────────────────────────────────────

resource "aws_security_group" "vpc_endpoints" {
  name        = "${var.cluster_name}-vpce-sg"
  description = "Allow HTTPS from within the VPC to interface endpoints"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-vpce-sg"
  })
}

# ── ECR API endpoint (interface) ──────────────────────────────────────────────

resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-ecr-api-vpce"
  })
}

# ── ECR Docker endpoint (interface) ───────────────────────────────────────────

resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-ecr-dkr-vpce"
  })
}

# ── S3 Gateway endpoint (free, no ENI) ───────────────────────────────────────

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [module.vpc.private_route_table_id]

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-s3-vpce"
  })
}

# ── STS endpoint (interface) — required for IRSA token exchange ───────────────

resource "aws_vpc_endpoint" "sts" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.sts"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-sts-vpce"
  })
}

# ── EC2 endpoint (interface) — used by EKS node lifecycle management ──────────

resource "aws_vpc_endpoint" "ec2" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ec2"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-ec2-vpce"
  })
}
