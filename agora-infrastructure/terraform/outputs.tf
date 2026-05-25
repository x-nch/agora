output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "vpc_private_subnets" {
  description = "Private subnet IDs"
  value       = module.vpc.private_subnets
}

output "vpc_database_subnets" {
  description = "Database subnet IDs"
  value       = module.vpc.database_subnets
}

output "eks_cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}

output "eks_cluster_ca_certificate" {
  description = "EKS cluster CA certificate"
  value       = module.eks.cluster_ca_certificate
  sensitive   = true
}

output "eks_cluster_arn" {
  description = "EKS cluster ARN"
  value       = module.eks.cluster_arn
}

output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "eks_oidc_issuer_url" {
  description = "EKS OIDC issuer URL"
  value       = module.eks.oidc_issuer_url
}

output "msk_bootstrap_brokers_tls" {
  description = "MSK TLS bootstrap brokers (port 9096)"
  value       = module.msk.bootstrap_brokers_tls
}

output "msk_bootstrap_brokers_iam" {
  description = "MSK IAM bootstrap brokers (port 9098)"
  value       = module.msk.bootstrap_brokers_iam
}

output "msk_cluster_arn" {
  description = "MSK cluster ARN"
  value       = module.msk.cluster_arn
}

output "aurora_endpoint" {
  description = "Aurora writer endpoint"
  value       = module.rds.cluster_endpoint
}

output "aurora_reader_endpoint" {
  description = "Aurora reader endpoint"
  value       = module.rds.reader_endpoint
}

output "aurora_secret_arn" {
  description = "Secrets Manager ARN for DB credentials"
  value       = module.rds.secret_arn
}

output "s3_data_lake_bucket_arn" {
  description = "Data lake bucket ARN"
  value       = module.s3.data_lake_bucket_arn
}

output "s3_app_logs_bucket_arn" {
  description = "App logs bucket ARN"
  value       = module.s3.app_logs_bucket_arn
}

output "s3_access_logs_bucket_arn" {
  description = "Access logs bucket ARN"
  value       = module.s3.access_logs_bucket_arn
}

output "s3_backups_bucket_arn" {
  description = "Backups bucket ARN"
  value       = module.s3.backups_bucket_arn
}

output "sns_critical_topic_arn" {
  description = "Critical SNS topic ARN for PagerDuty"
  value       = module.monitoring.sns_critical_topic_arn
}

output "sns_warning_topic_arn" {
  description = "Warning SNS topic ARN for Slack"
  value       = module.monitoring.sns_warning_topic_arn
}

output "sns_dr_topic_arn" {
  description = "DR SNS topic ARN for state lock and backup alerts"
  value       = module.monitoring.sns_dr_topic_arn
}

output "amp_workspace_id" {
  description = "Amazon Managed Prometheus workspace ID"
  value       = module.monitoring.amp_workspace_id
}

output "iam_roles" {
  description = "Map of IAM role ARNs created for IRSA"
  value       = module.iam.msk_irsa_roles
}

output "s3_data_lake_access_role_arn" {
  description = "Cross-account data lake access IAM role ARN"
  value       = module.iam.s3_data_lake_access_role_arn
}

output "s3_data_lake_access_policy_arn" {
  description = "Data lake access IAM policy ARN"
  value       = module.iam.s3_data_lake_access_policy_arn
}
