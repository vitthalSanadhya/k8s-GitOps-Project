# AWS EKS GitOps Platform — Terraform, ArgoCD & NGINX

Production-style **CI/CD infrastructure** on AWS: Terraform provisions an **Amazon EKS** cluster, **ArgoCD** continuously deploys application manifests from Git, and **NGINX** runs as a sample workload with optional **ALB Ingress**.

[![Terraform](https://img.shields.io/badge/IaC-Terraform-844FBA)](https://www.terraform.io/)
[![Kubernetes](https://img.shields.io/badge/Orchestration-EKS-326CE5)](https://aws.amazon.com/eks/)
[![GitOps](https://img.shields.io/badge/CD-ArgoCD-EF7B4D)](https://argo-cd.readthedocs.io/)

---

## Overview

| Layer | Technology | Responsibility |
|-------|------------|----------------|
| **Infrastructure** | Terraform | VPC, IAM, EKS cluster, managed node groups, ALB IRSA |
| **Continuous Integration** | GitHub Actions | `terraform fmt` / `validate` / `plan` / `apply` |
| **Continuous Delivery** | ArgoCD | Sync `manifests/` from this repository to the cluster |
| **Application** | Kubernetes | NGINX Deployment, Service, ConfigMap, optional Ingress |

**Design principles:** Infrastructure and application lifecycles are separated — changes under `terraform/` flow through CI; changes under `manifests/` flow through GitOps.

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                        GitHub Repository                         │
│  terraform/  ──► GitHub Actions (CI)  ──► AWS (EKS, VPC, IAM)  │
│  manifests/  ──► ArgoCD (CD)          ──► NGINX on EKS           │
│  argocd/     ──► ArgoCD bootstrap config                         │
└──────────────────────────────────────────────────────────────────┘

Developer access (dev):
  • ArgoCD UI  → kubectl port-forward → https://localhost:8080
  • NGINX app  → kubectl port-forward → http://localhost:8081

Optional (Ingress bonus):
  Internet → AWS ALB → Ingress → Service → Pods
```

**Current dev topology (`us-east-1`):** 2 availability zones, 1 NAT gateway, 1× `t3.small` worker node, Kubernetes **1.30**, control-plane logging disabled for cost control.

---

## Repository Structure

```
.
├── terraform/                 # AWS infrastructure (modular Terraform)
│   ├── backend.tf             # S3 remote state (us-east-1)
│   ├── main.tf                # Root module orchestration
│   ├── variables.tf
│   ├── outputs.tf
│   ├── alb_irsa.tf            # ALB Ingress Controller IAM (IRSA)
│   ├── tfvars/dev.tfvars      # Environment-specific values
│   ├── VPC/                   # VPC, subnets, IGW, NAT
│   ├── IAM/                   # EKS cluster & node IAM roles
│   └── EKS/                   # Cluster, node groups, OIDC, security groups
│
├── manifests/                 # Kubernetes application manifests
│   ├── nginx-configmap.yaml
│   ├── nginx-deployment.yaml
│   ├── nginx-service.yaml
│   └── nginx-ingress.yaml     # Optional: AWS ALB Ingress
│
├── argocd/                    # GitOps configuration
│   ├── install.sh             # Bootstrap ArgoCD + ALB controller
│   ├── project.yaml           # AppProject (RBAC / scope)
│   └── nginx-application.yaml # Application → manifests/
│
└── .github/workflows/         # CI pipelines
    ├── terraform.yml
    └── argocd-sync.yml
```

---

## Prerequisites

| Tool | Minimum version |
|------|-----------------|
| [Terraform](https://developer.hashicorp.com/terraform/install) | 1.10.0 |
| [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) | 2.x |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | 1.28 |
| [Helm](https://helm.sh/docs/intro/install/) | 3.12 (Ingress / install script) |
| Git | — |

Configure AWS credentials and verify access:

```bash
aws configure
aws sts get-caller-identity
```

---

## Quick Start

### 1. Bootstrap Terraform state (one-time)

```bash
aws s3 mb s3://apps-terraform-vs-use1 --region us-east-1

aws s3api put-bucket-versioning \
  --bucket apps-terraform-vs-use1 \
  --versioning-configuration Status=Enabled

aws s3api put-public-access-block \
  --bucket apps-terraform-vs-use1 \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
```

### 2. Provision infrastructure

```bash
cd terraform
terraform init
terraform plan -var-file=tfvars/dev.tfvars -out=tfplan
terraform apply tfplan
```

### 3. Configure kubectl

```bash
aws eks update-kubeconfig --region us-east-1 --name AppS-dev-eks
kubectl get nodes
```

### 4. Install ArgoCD and register the application

**Linux / macOS / Git Bash:**

```bash
cd argocd
chmod +x install.sh
./install.sh AppS-dev-eks us-east-1
```

**Manual install:**

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.10.0/manifests/install.yaml
kubectl apply -f argocd/project.yaml
kubectl apply -f argocd/nginx-application.yaml
```

ArgoCD watches `manifests/` on branch `main` with automated sync, prune, and self-heal enabled.

---

## Accessing Services

### ArgoCD UI

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

| | |
|---|---|
| **URL** | https://localhost:8080 |
| **Username** | `admin` |
| **Password** | See command below |

```bash
# Linux / macOS
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d && echo
```

```powershell
# Windows PowerShell
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | ForEach-Object { [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_)) }
```

Accept the TLS warning (self-signed certificate). Change the password after first login via **User Info → Update Password**.

### NGINX application

```bash
kubectl get pods -l app=nginx
kubectl port-forward svc/nginx 8081:80
```

Open **http://localhost:8081** or run `curl http://localhost:8081` — expect the NGINX welcome page.

---

## Assignment Requirements Mapping

| Requirement | Implementation |
|-------------|----------------|
| Terraform EKS (VPC, IAM, node groups, outputs) | `terraform/` modules |
| NGINX Kubernetes manifests | `manifests/` |
| ArgoCD on EKS + Application to Git | `argocd/` |
| Access NGINX | Port-forward (or LoadBalancer / Ingress) |
| Optional Ingress + DNS | `nginx-ingress.yaml` + AWS Load Balancer Controller |

---

## Optional: Ingress and AWS ALB

1. Install the [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/) using the IAM role from `terraform output -raw alb_controller_role_arn` and `terraform output -raw vpc_id`.
2. Update the host in `manifests/nginx-ingress.yaml` and push to `main`.
3. Verify: `kubectl get ingress nginx-ingress` (wait for `ADDRESS`).
4. Point DNS (Route 53 alias or CNAME) to the ALB hostname.

On a single small node, ensure sufficient pod capacity before installing the controller.

---

## CI/CD — GitHub Actions

| Workflow | Trigger | Behavior |
|----------|---------|----------|
| `terraform.yml` | Push/PR to `terraform/` | Validate → Plan (PR comment) → Apply (`main`) |
| `argocd-sync.yml` | Push to `manifests/` or `argocd/` | Commit notification (ArgoCD handles sync) |

**Required repository secrets** (`Settings → Secrets and variables → Actions`):

| Secret | Example value |
|--------|----------------|
| `AWS_ACCESS_KEY_ID` | IAM user access key |
| `AWS_SECRET_ACCESS_KEY` | IAM user secret |
| `AWS_REGION` | `us-east-1` |
| `TF_STATE_BUCKET` | `apps-terraform-vs-use1` |
| `EKS_CLUSTER_NAME` | `AppS-dev-eks` |

---

## Configuration Reference

Key settings in `terraform/tfvars/dev.tfvars`:

| Variable | Dev value | Notes |
|----------|-----------|-------|
| `aws_region` | `us-east-1` | Deployment region |
| `kubernetes_version` | `1.30` | EKS control plane |
| `single_nat_gateway` | `true` | Cost optimization |
| `cluster_log_types` | `[]` | Disables control-plane logs |
| Node instance type | `t3.small` | Free Tier–compatible on many accounts |
| Node count | `1` | Minimal dev capacity |

Terraform outputs: `cluster_name`, `cluster_endpoint`, `alb_controller_role_arn`, `vpc_id`, `kubeconfig` (sensitive).

---

## Security Notes

- EKS API endpoint is publicly reachable (`endpoint_public_access = true`) — restrict `public_access_cidrs` in production.
- Remote state is encrypted in S3 with native locking (`use_lockfile = true`).
- ALB permissions use **IRSA** (pod-scoped IAM), not node-wide credentials.
- Never commit AWS keys, `tfplan`, or `*.tfstate` files (see `.gitignore`).

---

## Troubleshooting

| Symptom | Likely cause | Action |
|---------|--------------|--------|
| `no nodes available to schedule pods` | Node group not ready | `kubectl get nodes`; check EKS node group status |
| EC2 launch failure (Free Tier) | Instance type not allowed | Use `t3.small` in `dev.tfvars` |
| ArgoCD `OutOfSync` | Git URL or branch mismatch | Verify `nginx-application.yaml` `repoURL` |
| Ingress has no `ADDRESS` | ALB controller missing | Install controller with `vpcId` and IRSA role |
| Port-forward connection refused | Forward process stopped | Re-run port-forward in a dedicated terminal |

---

## Cleanup

```bash
kubectl delete -f argocd/nginx-application.yaml --ignore-not-found
kubectl delete -f argocd/project.yaml --ignore-not-found

cd terraform
terraform destroy -var-file=tfvars/dev.tfvars
```

Confirm in the AWS Console that no load balancers or EBS volumes remain.

---

## Cost Estimate

Minimal dev deployment: approximately **$120–150 USD/month** (EKS control plane, one NAT gateway, one `t3.small` node). Destroy resources when not in use.

---

## License

This project is provided for educational and portfolio purposes. Review and adapt IAM policies before production use.

---

## Author

**Vitthal Sanadhya** — [k8s-GitOps-Project](https://github.com/vitthalSanadhya/k8s-GitOps-Project)
