variable "environment" {
  description = "Environment name"
  type        = string
}

variable "broker_type" {
  description = "MSK broker type: 'express' or 'serverless'"
  type        = string
}

variable "broker_node_count" {
  description = "Number of broker nodes (Express only)"
  type        = number
  default     = 3
}

variable "instance_type" {
  description = "MSK broker instance type"
  type        = string
  default     = "express.m7g.large"
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for MSK (must span 3 AZs for Express)"
  type        = list(string)
}

variable "kafka_version" {
  description = "Kafka version"
  type        = string
  default     = "3.6"
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
