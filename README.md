# EKS Platform Lab

An opinionated, end-to-end reference implementation of a modern Kubernetes platform on AWS EKS — bootstrapped via Terraform, then self-managed via GitOps.

Built as a personal reference for the patterns I'd use on day one of a platform engineering engagement: spot-first compute, declarative-everything, observability built in rather than bolted on, and a clean split between the bootstrap layer (Terraform) and the continuously-managed layer (Argo CD).

## What's in the stack

| Layer | Component | Why |
|---|---|---|
| Infrastructure | AWS VPC (single NAT) | Cost-tuned 3-AZ layout |
| Cluster | EKS 1.31, Pod Identity, AL2023 nodes | Modern auth; latest AMI family |
| Compute | Karpenter v1 (NodePool + EC2NodeClass) | Spot-first, fast scale, native consolidation |
| Bootstrap | Argo CD with root Application | App-of-apps pattern; everything below this line is Git-managed |
| Ingress | ingress-nginx (NLB) | Industry-standard, portable across clouds |
| TLS | cert-manager | Optional ClusterIssuer for self-signed or Let's Encrypt |
| Observability | kube-prometheus-stack (Grafana, Prom, Alertmanager) | Standard stack with preset dashboards and `ServiceMonitor`-based onboarding |
| Testing | Selenium Grid 4 | E2E test infrastructure |
| Sample workload | hello-world with Service, Ingress, ServiceMonitor, PrometheusRule | Demonstrates full app lifecycle in the platform |

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                          AWS Account                                 │
│                                                                      │
│   ┌──────────────────────────────────────────────────────────┐      │
│   │                       VPC (10.0.0.0/16)                  │      │
│   │   3x public subnet (NLBs)  +  3x private subnet (nodes)  │      │
│   │   Single NAT Gateway for cost                            │      │
│   └──────────────────────────────────────────────────────────┘      │
│                            │                                         │
│   ┌────────────────────────▼─────────────────────────────────┐      │
│   │                     EKS Cluster (1.31)                   │      │
│   │                                                          │      │
│   │   Bootstrap MNG (2x t3.medium)                           │      │
│   │     ├─ Karpenter controller                              │      │
│   │     ├─ Argo CD (root app watches your Git repo)          │      │
│   │     └─ System pods (CoreDNS, kube-proxy)                 │      │
│   │                                                          │      │
│   │   Karpenter NodePool "default" (spot, c/m/r families)    │      │
│   │     ├─ ingress-nginx (NLB-backed)                        │      │
│   │     ├─ cert-manager                                      │      │
│   │     ├─ kube-prometheus-stack (Grafana, Prom, AM)         │      │
│   │     ├─ Selenium Grid (hub + chrome nodes)                │      │
│   │     └─ hello-world (sample app)                          │      │
│   └──────────────────────────────────────────────────────────┘      │
└─────────────────────────────────────────────────────────────────────┘

         ▲                            ▲
         │ kubectl                    │ git push
         │                            │
    ┌────┴───┐                  ┌────┴─────────┐
    │  Ops   │                  │ GitHub repo  │  ← Argo CD watches this
    └────────┘                  └──────────────┘
```

## Design choices worth calling out

- **Two-phase bootstrap.** Terraform handles VPC → EKS → Karpenter controller → Argo CD. Everything else is GitOps. The line between "what Terraform owns" and "what Argo CD owns" is deliberate — Terraform owns things that need AWS API privileges or that the cluster itself depends on; Argo CD owns everything in-cluster from there.

- **App-of-apps pattern.** A single root Application is the only thing kubectl-applied. It watches `gitops/` recursively, where every YAML file is itself an Argo CD `Application`. Adding a new platform component is: drop a YAML, push, done.

- **Spot-first Karpenter NodePool.** Default NodePool accepts both spot and on-demand, c/m/r families, current generation, with `WhenEmptyOrUnderutilized` consolidation on a 30s timer. Real workloads needing on-demand can request it via node selector or topology constraints.

- **Bootstrap node group isolation.** Karpenter controller, Argo CD, and other meta-platform pods are pinned to the bootstrap MNG via `nodeSelector`. This prevents the chicken-and-egg of Karpenter running on a node it might decide to consolidate.

- **ServiceMonitor as the onboarding contract.** kube-prometheus-stack is configured to discover any ServiceMonitor or PrometheusRule in the cluster (not just those with the helm release label). Application teams onboard by shipping a ServiceMonitor alongside their Service. No platform intervention needed.

- **No DNS / TLS by default.** Lab uses sslip.io for free wildcard DNS against the NLB hostname. A `cert-manager` ClusterIssuer is provided as opt-in. Real Let's Encrypt + external-dns is documented but not deployed by default to keep the cost floor low.

## Cost expectations

This is **not free**. Concrete numbers:

| Resource | Cost | Notes |
|---|---|---|
| EKS control plane | $0.10/hr | $2.40/day. Unavoidable. |
| Bootstrap nodes (2x t3.medium) | ~$0.08/hr | $1.92/day |
| Karpenter spot nodes | ~$0.02–0.10/hr each | Only when scheduled |
| Single NAT Gateway | $0.045/hr + data | $1.08/day idle |
| NLB | $0.025/hr + LCU | ~$0.60/day |
| EBS volumes (Prom/AM) | trivial | ~$0.10/day |

**Idle cost: ~$5–6/day.** `terraform destroy` nightly if this is a learning lab. Production deployments scale up these costs but also justify them — this stack assumes you want production-grade patterns even at lab scale.

## Prerequisites

```bash
brew install awscli terraform kubectl helm jq
# Optional
brew install k9s argocd k6
```

AWS credentials configured (`aws sts get-caller-identity` should work).

A GitHub repo where you've pushed this code — Argo CD needs a Git source it can reach.

## Deploy

### 1. Push this code to your GitHub repo

```bash
git init
git add .
git commit -m "Initial commit"
git branch -M main
git remote add origin https://github.com/YOUR_USERNAME/YOUR_REPO.git
git push -u origin main
```

### 2. Configure Terraform

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: set gitops_repo_url to your GitHub repo URL
```

### 3. Apply Terraform in two phases

The Terraform helm/kubectl providers authenticate against the EKS cluster, which creates a chicken-and-egg on first apply. Resolve it with a targeted apply first:

```bash
terraform init

# Phase 1: Cluster + Karpenter infrastructure
terraform apply -target=module.vpc -target=module.eks -target=module.karpenter

# Phase 2: In-cluster resources (Karpenter helm, Argo CD, NodePool)
terraform apply
```

Total time: ~20 minutes.

### 4. Wire kubectl

```bash
$(terraform output -raw kubeconfig_command)
kubectl get nodes  # 2 bootstrap nodes should show
```

### 5. Update the hello-world Application repo URL

```bash
# From repo root
sed -i.bak "s|REPO_URL_PLACEHOLDER|https://github.com/YOUR_USERNAME/YOUR_REPO.git|" gitops/apps/hello-world.yaml
rm gitops/apps/hello-world.yaml.bak
git add gitops/apps/hello-world.yaml
git commit -m "Set hello-world repo URL"
git push
```

### 6. Watch Argo CD bootstrap everything

```bash
# Initial admin password
$(cd terraform && terraform output -raw argocd_initial_password_command)

# Port-forward
kubectl port-forward -n argocd svc/argocd-server 8080:80
# Browse http://localhost:8080, admin / <password>

# Or watch from CLI
kubectl get applications -n argocd -w
```

Bootstrap is complete when all Applications show `Healthy / Synced`. The order you'll see:
1. `root` (self-managing)
2. Projects sync
3. `ingress-nginx`, `cert-manager`, `kube-prometheus-stack`, `selenium-grid` (parallel)
4. `hello-world`

## Validate

### Karpenter scaling

```bash
kubectl apply -f karpenter-test/inflate.yaml
kubectl scale deployment inflate --replicas=20

# Watch nodes appear (~1-2 min on spot)
watch -n 5 'kubectl get nodes -L karpenter.sh/capacity-type,node.kubernetes.io/instance-type'

# Karpenter's decision log
kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter -f
```

Scale down to test consolidation:

```bash
kubectl scale deployment inflate --replicas=0
# Within 30s, Karpenter terminates empty nodes
```

### Grafana

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
# http://localhost:3000  •  admin / labadmin
```

Start with **Dashboards → Kubernetes / Compute Resources / Cluster**. Try some PromQL in Explore:

- `up` — scrape target health
- `rate(http_requests_total{job="hello"}[1m])` — RPS to the sample app
- `node_memory_MemAvailable_bytes` — node memory headroom

### Ingress + sample app

```bash
LB=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Update sample app ingress hostname
sed -i.bak "s|LB_HOSTNAME|${LB}|" apps/hello-world/ingress.yaml
rm apps/hello-world/ingress.yaml.bak
git add apps/hello-world/ingress.yaml
git commit -m "Set ingress LB hostname"
git push
# Argo CD picks up the change within a minute

curl http://hello.${LB}.sslip.io/
```

### Selenium Grid

```bash
kubectl port-forward -n selenium svc/selenium-hub 4444:4444
# UI at http://localhost:4444

pip install selenium
python loadtest/selenium-test.py
```

### GitOps self-heal

The killer demo for showing what Argo CD actually does:

```bash
# Make a change in Git
sed -i.bak 's/replicas: 2/replicas: 4/' apps/hello-world/deployment.yaml
rm apps/hello-world/deployment.yaml.bak
git commit -am "Scale hello-world to 4 replicas"
git push

# Within ~60s, Argo CD applies the change
kubectl get pods -n hello -w

# Now manually bypass GitOps
kubectl scale deployment -n hello hello --replicas=1
# Within 60s, Argo CD reverts you back to 4
```

### Load test + Karpenter scale, combined

Three panes (tmux or terminals):

```bash
# Pane 1 — load
LB=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
BASE_URL=http://hello.${LB}.sslip.io k6 run loadtest/hello-load.js

# Pane 2 — Karpenter
kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter -f

# Pane 3 — nodes
watch -n 2 'kubectl get nodes -L karpenter.sh/capacity-type,node.kubernetes.io/instance-type'
```

Then in Grafana, open the **NGINX Ingress controller** dashboard and watch RPS climb.

## Optional add-ons

### cert-manager ClusterIssuer (self-signed)

After cert-manager is healthy:

```bash
kubectl apply -f optional/cluster-issuer.yaml
```

### Real Let's Encrypt + external-dns

Requires a domain and Route53 hosted zone. The `optional/cluster-issuer.yaml` file has commented templates for `letsencrypt-staging` and `letsencrypt-prod`. external-dns isn't included by default — easy add as another Argo CD Application.

## Teardown

Order matters here. Argo CD owns resources outside Terraform's state (load balancers, ENIs); deleting the cluster without first cleaning these up will leave orphans that block VPC destruction.

```bash
# 1. Delete the root Application — Argo CD prunes everything downstream
kubectl delete application root -n argocd

# 2. Wait for pruning to complete
kubectl get applications -n argocd  # should empty out

# 3. Delete the ingress-nginx Service explicitly if it lingers (the LB needs to go)
kubectl delete svc -n ingress-nginx ingress-nginx-controller --ignore-not-found

# 4. Now destroy infrastructure
cd terraform
terraform destroy
```

If `terraform destroy` hangs on VPC deletion, it's almost always an orphaned ENI from a LoadBalancer. Find it in the AWS console (EC2 → Network Interfaces → filter by VPC), confirm it's unattached, delete manually, retry destroy.

## Repo layout

```
.
├── terraform/                   VPC + EKS + Karpenter + Argo CD bootstrap
├── gitops/                      Argo CD watches this folder
│   ├── projects/                AppProject definitions
│   ├── platform/                Platform-tier Applications (helm wrappers)
│   └── apps/                    Workload Applications
├── apps/                        Workload manifests referenced by gitops/apps/*
│   └── hello-world/
├── karpenter-test/              Scaling demo workload
├── loadtest/                    k6 + Selenium examples
└── optional/                    Opt-in components (ClusterIssuer)
```

## Troubleshooting

**Terraform apply fails on helm provider auth.** Skipped the two-phase apply. Run `terraform apply -target=module.vpc -target=module.eks -target=module.karpenter` first.

**Argo CD Applications stuck OutOfSync.** Check `kubectl describe app -n argocd <name>`. Usually: repo URL wrong, repo not publicly readable, or a CRD doesn't exist yet (race during initial bootstrap — Argo will retry).

**Karpenter not provisioning nodes.** Look at `kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter --tail=200`. Common causes: subnet tags missing (`karpenter.sh/discovery=<cluster_name>`), no spot capacity in the AZ, or a NodePool requirement that no instance type satisfies.

**Ingress LB never gets a public hostname.** `kubectl describe svc -n ingress-nginx ingress-nginx-controller` — read the events. Almost always missing public subnet tag `kubernetes.io/role/elb=1`.

## License

MIT — see [LICENSE](LICENSE).
