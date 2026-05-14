variable "region" {
  description = "AWS region for the lab"
  type        = string
  default     = "us-west-2"
}

variable "cluster_name" {
  description = "EKS cluster name. Used as a prefix on many resources."
  type        = string
  default     = "platform-lab"
}

variable "cluster_version" {
  description = "EKS Kubernetes version"
  type        = string
  default     = "1.31"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "gitops_repo_url" {
  description = "HTTPS URL of the Git repo Argo CD will watch (your fork of this lab). Example: https://github.com/YOUR_USERNAME/YOUR_REPO.git"
  type        = string
}

variable "gitops_repo_branch" {
  description = "Branch Argo CD watches"
  type        = string
  default     = "main"
}

variable "tags" {
  description = "Default tags applied to all resources"
  type        = map(string)
  default = {
    Project   = "platform-lab"
    ManagedBy = "terraform"
    Owner     = "adam"
  }
}
