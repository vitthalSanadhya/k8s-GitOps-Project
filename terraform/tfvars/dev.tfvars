# ── AppS / dev — minimal cost (us-east-1) ─────────────────
aws_region         = "us-east-1"
project_name       = "AppS"
environment        = "dev"
single_nat_gateway = true

# VPC — 2 AZs (EKS minimum); 1 NAT gateway
vpc_cidr             = "10.0.0.0/16"
availability_zones   = ["us-east-1a", "us-east-1b"]
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]

# EKS — disable control-plane logs to save cost
kubernetes_version = "1.30"
cluster_log_types  = []

node_groups = {
  general = {
    instance_types = ["t3.small"]
    capacity_type  = "ON_DEMAND"
    desired_size   = 1
    min_size       = 1
    max_size       = 1
    disk_size_gb   = 20
    labels         = { role = "general", env = "dev" }
    taints         = []
  }
}
