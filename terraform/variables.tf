###############################################################
# Root Variables
###############################################################

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "single_nat_gateway" {
  description = "Use one NAT gateway for all private subnets (lower cost)"
  type        = bool
  default     = true
}

variable "project_name" {
  description = "Project / application name used as a prefix for all resources"
  type        = string
  default     = "AppS"
}

variable "environment" {
  description = "Deployment environment (dev | staging | prod)"
  type        = string
  default     = "dev"
}

# ── VPC ───────────────────────────────────────────────────────
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of AZs to use (must match subnet lists)"
  type        = list(string)
  default     = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "At least two availability zones are required for HA."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
}

check "subnet_az_alignment" {
  assert {
    condition = (
      length(var.availability_zones) == length(var.public_subnet_cidrs) &&
      length(var.availability_zones) == length(var.private_subnet_cidrs)
    )
    error_message = "availability_zones, public_subnet_cidrs, and private_subnet_cidrs must have the same length."
  }
}

# ── EKS ───────────────────────────────────────────────────────
variable "kubernetes_version" {
  description = "Kubernetes control-plane version"
  type        = string
  default     = "1.29"
}

variable "cluster_log_types" {
  description = "EKS control-plane log types to enable"
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

variable "node_groups" {
  description = "Map of managed node-group configurations"
  type = map(object({
    instance_types = list(string)
    capacity_type  = string # ON_DEMAND | SPOT
    desired_size   = number
    min_size       = number
    max_size       = number
    disk_size_gb   = number
    labels         = map(string)
    taints = list(object({
      key    = string
      value  = string
      effect = string
    }))
  }))
  default = {
    general = {
      instance_types = ["t3.medium"]
      capacity_type  = "ON_DEMAND"
      desired_size   = 2
      min_size       = 1
      max_size       = 4
      disk_size_gb   = 50
      labels         = { role = "general" }
      taints         = []
    }
    spot = {
      instance_types = ["t3.large", "t3a.large"]
      capacity_type  = "SPOT"
      desired_size   = 1
      min_size       = 0
      max_size       = 6
      disk_size_gb   = 50
      labels         = { role = "spot" }
      taints = [{
        key    = "spot"
        value  = "true"
        effect = "NO_SCHEDULE"
      }]
    }
  }
}
