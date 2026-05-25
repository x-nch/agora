output "msk_irsa_roles" {
  description = "Map of service names to IAM role ARNs for MSK IRSA"
  value = {
    traffic-optimizer = aws_iam_role.traffic_optimizer_msk.arn
    anomaly-detector  = aws_iam_role.anomaly_detector_msk.arn
    energy-optimizer  = aws_iam_role.energy_optimizer_msk.arn
    data-broker       = aws_iam_role.data_broker_msk.arn
    kafka-connect     = aws_iam_role.kafka_connect_msk.arn
    schema-registry   = aws_iam_role.schema_registry_msk.arn
  }
}

output "s3_data_lake_access_role_arn" {
  description = "IAM role ARN for cross-account data lake access"
  value       = try(aws_iam_role.s3_data_lake_cross_account[0].arn, null)
}

output "s3_data_lake_access_policy_arn" {
  description = "IAM policy ARN for data lake access"
  value       = aws_iam_policy.s3_data_lake_access.arn
}
