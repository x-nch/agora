variable "environment" {
  description = "Environment name"
  type        = string
}

variable "alarm_notification_email" {
  description = "Email for alarm notifications"
  type        = string
}

variable "sns_topic_prefix" {
  description = "Prefix for SNS topic names"
  type        = string
}

variable "amp_workspace_alias" {
  description = "Alias for AMP workspace"
  type        = string
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
