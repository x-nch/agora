# Security group for Aurora
resource "aws_security_group" "aurora" {
  name        = "agora-${var.environment}-aurora"
  description = "Security group for Aurora PostgreSQL"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL from EKS cluster"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = var.eks_cluster_security_group_id != null ? [var.eks_cluster_security_group_id] : []
    cidr_blocks     = var.eks_cluster_security_group_id != null ? [] : [data.aws_vpc.selected.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "agora-${var.environment}-aurora-sg"
  })
}

data "aws_vpc" "selected" {
  id = var.vpc_id
}
