output "bootstrap_brokers_tls" {
  description = "TLS bootstrap broker string (port 9096; serverless returns IAM string)"
  value       = try(aws_msk_cluster.express[0].bootstrap_brokers_tls, aws_msk_serverless_cluster.serverless[0].bootstrap_brokers_sasl_iam)
}

output "bootstrap_brokers_iam" {
  description = "IAM bootstrap broker string (port 9098)"
  value       = try(aws_msk_cluster.express[0].bootstrap_brokers_sasl_iam, aws_msk_serverless_cluster.serverless[0].bootstrap_brokers_sasl_iam)
}

output "cluster_arn" {
  description = "MSK cluster ARN"
  value       = try(aws_msk_cluster.express[0].arn, aws_msk_serverless_cluster.serverless[0].arn)
}

output "cluster_name" {
  description = "MSK cluster name"
  value       = try(aws_msk_cluster.express[0].cluster_name, aws_msk_serverless_cluster.serverless[0].cluster_name)
}

output "security_group_id" {
  description = "MSK security group ID"
  value       = aws_security_group.msk.id
}

output "zookeeper_connect_string" {
  description = "ZooKeeper connect string (Express only)"
  value       = var.broker_type == "express" ? aws_msk_cluster.express[0].zookeeper_connect_string : null
}
