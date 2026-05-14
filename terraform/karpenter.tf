# The Karpenter sub-module creates the IAM roles, instance profile, and SQS queue
# Karpenter needs. Pod Identity (not IRSA) is the modern approach.
module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 20.31"

  cluster_name = module.eks.cluster_name

  enable_pod_identity             = true
  create_pod_identity_association = true

  # Lets Karpenter-launched nodes reach SSM (Session Manager debugging).
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }
}

# Install the Karpenter controller via Helm.
resource "helm_release" "karpenter" {
  namespace     = "kube-system"
  name          = "karpenter"
  repository    = "oci://public.ecr.aws/karpenter"
  chart         = "karpenter"
  version       = "1.1.1"
  wait          = true
  wait_for_jobs = true

  values = [
    yamlencode({
      settings = {
        clusterName       = module.eks.cluster_name
        clusterEndpoint   = module.eks.cluster_endpoint
        interruptionQueue = module.karpenter.queue_name
      }
      serviceAccount = {
        name = "karpenter"
      }
      controller = {
        resources = {
          requests = { cpu = "200m", memory = "256Mi" }
          limits   = { cpu = "1", memory = "1Gi" }
        }
      }
      # Schedule controller pods on the bootstrap node group, not on Karpenter-managed nodes
      # (which would create a chicken-and-egg if all nodes go away).
      nodeSelector = {
        "node-role" = "bootstrap"
      }
    })
  ]

  depends_on = [
    module.karpenter,
    module.eks
  ]
}

# Default EC2NodeClass — defines the AWS-level shape of nodes Karpenter creates.
resource "kubectl_manifest" "karpenter_ec2nodeclass_default" {
  yaml_body = <<-YAML
    apiVersion: karpenter.k8s.aws/v1
    kind: EC2NodeClass
    metadata:
      name: default
    spec:
      amiFamily: AL2023
      role: ${module.karpenter.node_iam_role_name}
      subnetSelectorTerms:
        - tags:
            karpenter.sh/discovery: ${var.cluster_name}
      securityGroupSelectorTerms:
        - tags:
            karpenter.sh/discovery: ${var.cluster_name}
      amiSelectorTerms:
        - alias: al2023@latest
      tags:
        karpenter.sh/discovery: ${var.cluster_name}
        Project: ${var.cluster_name}
  YAML

  depends_on = [helm_release.karpenter]
}

# Default NodePool — Karpenter's K8s-level scheduling rules.
# Spot-first, c/m/r instance families, current-gen only, x86 + arm64.
resource "kubectl_manifest" "karpenter_nodepool_default" {
  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1
    kind: NodePool
    metadata:
      name: default
    spec:
      template:
        metadata:
          labels:
            nodepool: default
        spec:
          requirements:
            - key: karpenter.k8s.aws/instance-category
              operator: In
              values: ["c", "m", "r"]
            - key: karpenter.k8s.aws/instance-cpu
              operator: In
              values: ["2", "4", "8"]
            - key: karpenter.k8s.aws/instance-generation
              operator: Gt
              values: ["3"]
            - key: karpenter.sh/capacity-type
              operator: In
              values: ["spot", "on-demand"]
            - key: kubernetes.io/arch
              operator: In
              values: ["amd64"]
            - key: kubernetes.io/os
              operator: In
              values: ["linux"]
          nodeClassRef:
            group: karpenter.k8s.aws
            kind: EC2NodeClass
            name: default
          expireAfter: 720h
      limits:
        cpu: "100"
        memory: 400Gi
      disruption:
        consolidationPolicy: WhenEmptyOrUnderutilized
        consolidateAfter: 30s
  YAML

  depends_on = [kubectl_manifest.karpenter_ec2nodeclass_default]
}
