###############################################################
# Root Outputs — cluster access & key resource IDs
###############################################################

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_ca_certificate" {
  description = "Base64-encoded cluster certificate authority data"
  value       = module.eks.cluster_ca_certificate
  sensitive   = true
}

output "cluster_token" {
  description = "Authentication token for kubectl (short-lived)"
  value       = module.eks.cluster_token
  sensitive   = true
}

# ── Convenience: ready-to-use kubeconfig block ─────────────────
output "kubeconfig" {
  description = "Minimal kubeconfig to paste into ~/.kube/config"
  sensitive   = true
  value       = <<-EOT
    apiVersion: v1
    kind: Config
    clusters:
    - cluster:
        server: ${module.eks.cluster_endpoint}
        certificate-authority-data: ${module.eks.cluster_ca_certificate}
      name: ${module.eks.cluster_name}
    contexts:
    - context:
        cluster: ${module.eks.cluster_name}
        user: ${module.eks.cluster_name}-admin
      name: ${module.eks.cluster_name}
    current-context: ${module.eks.cluster_name}
    users:
    - name: ${module.eks.cluster_name}-admin
      user:
        token: ${module.eks.cluster_token}
  EOT
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs (EKS node subnets)"
  value       = module.vpc.private_subnet_ids
}

output "alb_controller_role_arn" {
  description = "IAM role ARN for AWS Load Balancer Controller (IRSA)"
  value       = aws_iam_role.alb_controller.arn
}
