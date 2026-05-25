output "data_lake_bucket_id" {
  description = "Data lake bucket ID"
  value       = aws_s3_bucket.data_lake.id
}

output "data_lake_bucket_arn" {
  description = "Data lake bucket ARN"
  value       = aws_s3_bucket.data_lake.arn
}

output "app_logs_bucket_id" {
  description = "App logs bucket ID"
  value       = aws_s3_bucket.app_logs.id
}

output "app_logs_bucket_arn" {
  description = "App logs bucket ARN"
  value       = aws_s3_bucket.app_logs.arn
}

output "access_logs_bucket_id" {
  description = "Access logs bucket ID"
  value       = aws_s3_bucket.access_logs.id
}

output "access_logs_bucket_arn" {
  description = "Access logs bucket ARN"
  value       = aws_s3_bucket.access_logs.arn
}

output "backups_bucket_id" {
  description = "Backups bucket ID"
  value       = aws_s3_bucket.backups.id
}

output "backups_bucket_arn" {
  description = "Backups bucket ARN"
  value       = aws_s3_bucket.backups.arn
}
