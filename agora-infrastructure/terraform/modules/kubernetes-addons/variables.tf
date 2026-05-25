variable "environment" {
  description = "Environment name"
  type        = string
}

variable "eks_cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "oidc_issuer_url" {
  description = "EKS OIDC issuer URL"
  type        = string
  default     = ""
}

variable "vpc_id" {
  description = "VPC ID (for AWS LB Controller)"
  type        = string
  default     = ""
}

variable "acme_email" {
  description = "Email for Let's Encrypt certificate notifications"
  type        = string
  default     = "admin@agora.woven-city.jp"
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

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
