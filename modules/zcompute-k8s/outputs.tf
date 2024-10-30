output "cluster_name" {
  value = try(var.cluster_name, null)
}
output "cluster_version" {
  value = try(var.cluster_version, null)
}
output "cluster_security_group_id" {
  description = "ID of the cluster security group"
  value       = try(aws_security_group.k8s.id, null)
}
