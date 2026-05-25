variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-1"
}

variable "environment" {
  description = "Environment name (dev/staging/production)"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
}

variable "database_subnet_cidrs" {
  description = "CIDR blocks for database subnets"
  type        = list(string)
}

variable "kubernetes_version" {
  description = "Kubernetes version for EKS"
  type        = string
  default     = "1.28"
}

variable "node_instance_types" {
  description = "EC2 instance types for EKS node groups"
  type        = list(string)
}

variable "desired_node_count" {
  description = "Desired number of EKS nodes"
  type        = number
}

variable "min_node_count" {
  description = "Minimum number of EKS nodes"
  type        = number
}

variable "max_node_count" {
  description = "Maximum number of EKS nodes"
  type        = number
}

variable "msk_broker_type" {
  description = "MSK broker type: 'express' or 'serverless'"
  type        = string
}

variable "msk_broker_count" {
  description = "Number of MSK Express brokers (ignored for serverless)"
  type        = number
  default     = 3
}

variable "msk_instance_type" {
  description = "MSK broker instance type"
  type        = string
  default     = "express.m7g.large"
}

variable "msk_kafka_version" {
  description = "Kafka version for MSK Express (requires 3.6+)"
  type        = string
  default     = "3.6"
}

variable "rds_instance_class" {
  description = "RDS instance class for Aurora"
  type        = string
}

variable "rds_serverless_min_capacity" {
  description = "Minimum ACU for Aurora Serverless v2"
  type        = number
  default     = 0.5
}

variable "rds_serverless_max_capacity" {
  description = "Maximum ACU for Aurora Serverless v2"
  type        = number
  default     = 2
}

variable "rds_reader_count" {
  description = "Number of Aurora reader replicas"
  type        = number
  default     = 0
}

variable "rds_multi_az" {
  description = "Enable Multi-AZ for Aurora"
  type        = bool
  default     = false
}

variable "rds_backup_retention_days" {
  description = "Backup retention days for Aurora"
  type        = number
  default     = 7
}

variable "rds_storage_gb" {
  description = "Minimum allocated storage for Aurora (auto-scaling)"
  type        = number
  default     = 100
}

variable "db_master_username" {
  description = "Aurora master username"
  type        = string
  default     = "agora_admin"
}

variable "data_lake_consumer_account_id" {
  description = "AWS account ID that consumes data lake data"
  type        = string
  default     = null
}

variable "ingress_load_balancer_scheme" {
  description = "NLB scheme for NGINX ingress controller"
  type        = string
  default     = "internal"
  validation {
    condition     = contains(["internal", "internet-facing"], var.ingress_load_balancer_scheme)
    error_message = "Must be 'internal' or 'internet-facing'."
  }
}

variable "acme_email" {
  description = "Email for Let's Encrypt certificate notifications"
  type        = string
  default     = "admin@agora.woven-city.jp"
}

variable "alarm_email" {
  description = "Email for CloudWatch alarm notifications"
  type        = string
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}
