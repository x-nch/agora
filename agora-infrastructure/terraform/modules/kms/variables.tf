variable "environment" {
  description = "Environment name"
  type        = string
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}

variable "eks_node_role_arns" {
  description = "IAM role ARNs for EKS nodes — granted kms:Encrypt/Decrypt for EBS and secrets"
  type        = list(string)
  default     = []
}
