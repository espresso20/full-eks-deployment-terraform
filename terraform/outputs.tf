output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_region" {
  description = "AWS region"
  value       = var.region
}

output "kubeconfig_command" {
  description = "Run this to wire kubectl to the lab cluster"
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

output "argocd_initial_password_command" {
  description = "Run this AFTER cluster is up to retrieve the Argo CD admin password"
  value       = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d ; echo"
}

output "argocd_port_forward_command" {
  description = "Run this to access the Argo CD UI at https://localhost:8080 (accept the cert warning)"
  value       = "kubectl port-forward -n argocd svc/argocd-server 8080:80"
}

output "karpenter_node_iam_role" {
  description = "IAM role assumed by Karpenter-launched nodes"
  value       = module.karpenter.node_iam_role_name
}

output "vpc_id" {
  value = module.vpc.vpc_id
}
