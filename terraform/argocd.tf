# Install Argo CD via Helm.
# Insecure mode is fine for lab — we'll port-forward over kubectl, no public exposure.
resource "helm_release" "argocd" {
  namespace        = "argocd"
  create_namespace = true
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "7.7.5"
  wait             = true
  timeout          = 600

  values = [
    yamlencode({
      global = {
        domain = "argocd.lab.local"
      }
      configs = {
        params = {
          # Run Argo CD server in HTTP mode — port-forward + browser, no TLS in lab.
          "server.insecure" = true
        }
      }
      # Pin Argo components to bootstrap nodes for stability.
      controller = {
        nodeSelector = { "node-role" = "bootstrap" }
      }
      server = {
        nodeSelector = { "node-role" = "bootstrap" }
        service = {
          type = "ClusterIP"
        }
      }
      repoServer = {
        nodeSelector = { "node-role" = "bootstrap" }
      }
      applicationSet = {
        nodeSelector = { "node-role" = "bootstrap" }
      }
      notifications = {
        nodeSelector = { "node-role" = "bootstrap" }
      }
      dex = {
        nodeSelector = { "node-role" = "bootstrap" }
      }
      redis = {
        nodeSelector = { "node-role" = "bootstrap" }
      }
    })
  ]

  depends_on = [module.eks]
}

# The root Application — app-of-apps pattern.
# This single Application tells Argo CD: "watch gitops/projects and gitops/platform in
# the lab repo, and create child Applications from whatever YAML you find."
# From here on out, the cluster's platform state lives in Git.
resource "kubectl_manifest" "argocd_root_app" {
  yaml_body = <<-YAML
    apiVersion: argoproj.io/v1alpha1
    kind: Application
    metadata:
      name: root
      namespace: argocd
      finalizers:
        - resources-finalizer.argocd.argoproj.io
    spec:
      project: default
      source:
        repoURL: ${var.gitops_repo_url}
        targetRevision: ${var.gitops_repo_branch}
        path: gitops
        directory:
          recurse: true
      destination:
        server: https://kubernetes.default.svc
        namespace: argocd
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
          - ServerSideApply=true
  YAML

  depends_on = [helm_release.argocd]
}
