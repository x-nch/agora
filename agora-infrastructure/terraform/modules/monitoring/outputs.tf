output "sns_critical_topic_arn" {
  description = "Critical SNS topic ARN"
  value       = aws_sns_topic.critical.arn
}

output "sns_warning_topic_arn" {
  description = "Warning SNS topic ARN"
  value       = aws_sns_topic.warning.arn
}

output "sns_info_topic_arn" {
  description = "Info SNS topic ARN"
  value       = aws_sns_topic.info.arn
}

output "sns_dr_topic_arn" {
  description = "DR SNS topic ARN for state lock and backup alerts"
  value       = aws_sns_topic.dr.arn
}

output "amp_workspace_id" {
  description = "AMP workspace ID"
  value       = aws_prometheus_workspace.main.id
}

output "amp_workspace_arn" {
  description = "AMP workspace ARN"
  value       = aws_prometheus_workspace.main.arn
}

output "dashboard_arns" {
  description = "CloudWatch dashboard names"
  value = [
    aws_cloudwatch_dashboard.eks.dashboard_name,
    aws_cloudwatch_dashboard.msk.dashboard_name,
    aws_cloudwatch_dashboard.aurora.dashboard_name,
    aws_cloudwatch_dashboard.dr.dashboard_name,
  ]
}
