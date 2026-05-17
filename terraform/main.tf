###############################################################
# AppS — Root Configuration
# Provisions: VPC → IAM → EKS
###############################################################

terraform {
  required_version = ">= 1.10.0" # 1.10+ required for S3 native locking

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

# ------------------------------------------------------------------
# VPC
# ------------------------------------------------------------------
module "vpc" {
  source = "./VPC"

  project_name         = var.project_name
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  single_nat_gateway   = var.single_nat_gateway
}

# ------------------------------------------------------------------
# IAM — base roles (cluster + node). ALB IRSA role added after EKS.
# ------------------------------------------------------------------
module "iam_base" {
  source = "./IAM"

  project_name = var.project_name
  environment  = var.environment
}

# ------------------------------------------------------------------
# EKS Cluster + Managed Node Groups
# ------------------------------------------------------------------
module "eks" {
  source = "./EKS"

  project_name       = var.project_name
  environment        = var.environment
  aws_region         = var.aws_region
  kubernetes_version = var.kubernetes_version

  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  public_subnet_ids  = module.vpc.public_subnet_ids

  cluster_role_arn = module.iam_base.eks_cluster_role_arn
  node_role_arn    = module.iam_base.eks_node_role_arn

  node_groups       = var.node_groups
  cluster_log_types = var.cluster_log_types

  depends_on = [module.iam_base]
}

# ------------------------------------------------------------------
# IAM — ALB Controller IRSA (needs EKS OIDC provider)
# Defined in alb_irsa.tf at root level to avoid count-on-unknown error
# ------------------------------------------------------------------
