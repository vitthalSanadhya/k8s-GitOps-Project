data "aws_eks_cluster_auth" "this" {
  name = aws_eks_cluster.this.name
}

output "cluster_name" {
  value = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.this.endpoint
}

output "cluster_ca_certificate" {
  value     = aws_eks_cluster.this.certificate_authority[0].data
  sensitive = true
}

output "cluster_token" {
  value     = data.aws_eks_cluster_auth.this.token
  sensitive = true
}

output "cluster_version" {
  value = aws_eks_cluster.this.version
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN — use for IRSA trust policies"
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "oidc_provider_url" {
  description = "OIDC provider URL (without https://)"
  value       = replace(aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")
}

output "node_security_group_id" {
  value = aws_security_group.nodes.id
}

output "node_group_names" {
  value = { for k, ng in aws_eks_node_group.this : k => ng.node_group_name }
}
