output "cluster_name" {
  value = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.this.endpoint
}

output "region" {
  value = var.region
}

output "configure_kubectl" {
  description = "Comando para configurar o kubeconfig"
  value       = "aws eks update-kubeconfig --name ${var.cluster_name} --region ${var.region}"
}

output "account_id" {
  value = data.aws_caller_identity.current.account_id
}
