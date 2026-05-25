terraform {
  backend "s3" {
    bucket         = "agora-terraform-state"
    key            = "staging/terraform.tfstate"
    region         = "ap-northeast-1"
    encrypt        = true
    dynamodb_table = "terraform-lock"
  }
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-1"
}

provider "aws" {
  region = var.region
}
