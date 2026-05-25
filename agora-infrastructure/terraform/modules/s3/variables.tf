variable "environment" {
  description = "Environment name"
  type        = string
}

variable "bucket_prefix" {
  description = "Prefix for bucket names"
  type        = string
  default     = "agora"
}

variable "versioning_enabled" {
  description = "Enable S3 versioning"
  type        = bool
  default     = true
}

variable "encryption_enabled" {
  description = "Enable KMS encryption"
  type        = bool
  default     = true
}

variable "kms_key_id" {
  description = "KMS key ARN for SSE-KMS encryption"
  type        = string
  default     = null
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
