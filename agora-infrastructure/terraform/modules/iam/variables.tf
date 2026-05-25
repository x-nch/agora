variable "environment" {
  description = "Environment name"
  type        = string
}

variable "eks_oidc_issuer_url" {
  description = "EKS OIDC issuer URL"
  type        = string
}

variable "msk_cluster_arn" {
  description = "MSK cluster ARN"
  type        = string
}

variable "s3_data_lake_bucket_arn" {
  description = "S3 data lake bucket ARN"
  type        = string
}

variable "data_lake_consumer_account_id" {
  description = "AWS account ID that consumes data lake data"
  type        = string
  default     = null
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
