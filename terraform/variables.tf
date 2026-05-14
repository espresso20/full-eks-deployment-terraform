variable "region" {
  description = "AWS region"
  type        = string
}

variable "aws_profile" {
  description = "AWS CLI profile name (SSO or otherwise). Null falls back to the default credential chain (env vars, ~/.aws/credentials)."
  type        = string
  default     = null
}

variable "cluster_name" {
  description = "EKS cluster name. Used as a prefix on many resources."
  type        = string
}

variable "cluster_version" {
  description = "EKS Kubernetes version"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
}

variable "gitops_repo_url" {
  description = "HTTPS URL of the Git repo Argo CD will watch. Example: https://github.com/YOUR_USERNAME/YOUR_REPO.git"
  type        = string
}

variable "gitops_repo_branch" {
  description = "Branch Argo CD watches"
  type        = string
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
