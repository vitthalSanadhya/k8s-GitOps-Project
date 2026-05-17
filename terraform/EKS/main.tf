###############################################################
# Module: EKS
# Creates: EKS Cluster, Security Groups, Managed Node Groups,
#          OIDC provider, aws-auth ConfigMap data
###############################################################

terraform {
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

locals {
  cluster_name = "${var.project_name}-${var.environment}-eks"
}

data "aws_caller_identity" "current" {}

# ── Cluster Security Group ─────────────────────────────────────
resource "aws_security_group" "cluster" {
  name        = "${local.cluster_name}-cluster-sg"
  description = "EKS cluster control-plane security group"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = { Name = "${local.cluster_name}-cluster-sg" }
}

# ── Node Security Group ───────────────────────────────────────
resource "aws_security_group" "nodes" {
  name        = "${local.cluster_name}-nodes-sg"
  description = "EKS worker nodes security group"
  vpc_id      = var.vpc_id

  # Nodes talk to each other freely
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
    description = "Node-to-node communication"
  }

  # Nodes accept traffic from control plane
  ingress {
    from_port       = 1025
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.cluster.id]
    description     = "Control plane to nodes (kubelet + services)"
  }

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.cluster.id]
    description     = "Control plane to nodes (webhooks)"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = { Name = "${local.cluster_name}-nodes-sg" }
}

# Allow nodes → control plane
resource "aws_security_group_rule" "nodes_to_cluster" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.cluster.id
  source_security_group_id = aws_security_group.nodes.id
  description              = "Nodes to control plane (metrics, kubectl exec)"
}

# ── EKS Cluster ───────────────────────────────────────────────
resource "aws_eks_cluster" "this" {
  name     = local.cluster_name
  role_arn = var.cluster_role_arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = concat(var.private_subnet_ids, var.public_subnet_ids)
    security_group_ids      = [aws_security_group.cluster.id]
    endpoint_private_access = true
    endpoint_public_access  = true # set false for fully private clusters
  }

  enabled_cluster_log_types = var.cluster_log_types

  # Encrypt secrets at rest with a managed KMS key
  # (Remove/comment the encryption_config block if not needed)
  # encryption_config {
  #   provider { key_arn = var.kms_key_arn }
  #   resources = ["secrets"]
  # }

  tags = { Name = local.cluster_name }
}

# ── OIDC Provider (required for IRSA) ────────────────────────
data "tls_certificate" "eks" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [for cert in data.tls_certificate.eks.certificates : cert.sha1_fingerprint]
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

# ── Launch templates (attach worker-node security group) ────────
resource "aws_launch_template" "node" {
  for_each = var.node_groups

  name_prefix            = "${local.cluster_name}-${each.key}-"
  vpc_security_group_ids = [aws_security_group.nodes.id]

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = each.value.disk_size_gb
      volume_type           = "gp3"
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${local.cluster_name}-${each.key}-node" }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ── Managed Node Groups ───────────────────────────────────────
resource "aws_eks_node_group" "this" {
  for_each = var.node_groups

  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${local.cluster_name}-${each.key}"
  node_role_arn   = var.node_role_arn
  subnet_ids      = var.private_subnet_ids

  instance_types = each.value.instance_types
  capacity_type  = each.value.capacity_type

  launch_template {
    id      = aws_launch_template.node[each.key].id
    version = aws_launch_template.node[each.key].latest_version
  }

  scaling_config {
    desired_size = each.value.desired_size
    min_size     = each.value.min_size
    max_size     = each.value.max_size
  }

  update_config {
    max_unavailable = 1
  }

  labels = each.value.labels

  dynamic "taint" {
    for_each = each.value.taints
    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }

  depends_on = [
    aws_eks_cluster.this,
    aws_launch_template.node,
    aws_security_group_rule.nodes_to_cluster,
  ]

  tags = { Name = "${local.cluster_name}-${each.key}" }

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size] # allow cluster-autoscaler to manage
  }
}

# ── aws-auth ConfigMap data (apply via kubectl or kubernetes provider) ──
# Uncomment the kubernetes provider block in the root if you want
# Terraform to manage aws-auth directly.
#
# resource "kubernetes_config_map_v1_data" "aws_auth" { ... }
