variable "environment" {
  description = "Environment name"
  type        = string
}

variable "db_name" {
  description = "Database name"
  type        = string
}

variable "master_username" {
  description = "Master username"
  type        = string
}


variable "instance_class" {
  description = "Instance class (e.g., db.serverless, db.r6g.xlarge)"
  type        = string
}

variable "serverless_min_capacity" {
  description = "Min ACU for Aurora Serverless v2"
  type        = number
  default     = 0.5
}

variable "serverless_max_capacity" {
  description = "Max ACU for Aurora Serverless v2"
  type        = number
  default     = 2
}

variable "reader_count" {
  description = "Number of Aurora reader replicas"
  type        = number
  default     = 0
}

variable "allocated_storage" {
  description = "Allocated storage in GB (Aurora auto-scaling)"
  type        = number
  default     = 100
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_ids" {
  description = "Database subnet IDs"
  type        = list(string)
}

variable "backup_retention_days" {
  description = "Backup retention days"
  type        = number
  default     = 7
}

variable "multi_az" {
  description = "Multi-AZ deployment"
  type        = bool
  default     = false
}

variable "engine_mode" {
  description = "Engine mode"
  type        = string
  default     = "aurora-postgresql"
}

variable "eks_cluster_security_group_id" {
  description = "EKS cluster security group ID"
  type        = string
  default     = null
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
