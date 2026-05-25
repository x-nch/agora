data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_name
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(var.tags, {
      Environment = var.environment
      Project     = "agora"
      ManagedBy   = "terraform"
    })
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}

module "vpc" {
  source = "./modules/vpc"

  environment           = var.environment
  vpc_cidr              = var.vpc_cidr
  availability_zones    = var.availability_zones
  public_subnet_cidrs   = var.public_subnet_cidrs
  private_subnet_cidrs  = var.private_subnet_cidrs
  database_subnet_cidrs = var.database_subnet_cidrs
  tags                  = var.tags
}

module "eks" {
  source = "./modules/eks"

  environment         = var.environment
  cluster_name        = "agora-${var.environment}"
  kubernetes_version  = var.kubernetes_version
  vpc_id              = module.vpc.vpc_id
  subnet_ids          = module.vpc.private_subnets
  node_instance_types = var.node_instance_types
  desired_size        = var.desired_node_count
  min_size            = var.min_node_count
  max_size            = var.max_node_count
  tags                = var.tags
}

module "msk" {
  source = "./modules/msk"

  environment                   = var.environment
  broker_type                   = var.msk_broker_type
  broker_node_count             = var.msk_broker_count
  instance_type                 = var.msk_instance_type
  vpc_id                        = module.vpc.vpc_id
  subnet_ids                    = module.vpc.private_subnets
  kafka_version                 = var.msk_kafka_version
  eks_cluster_security_group_id = module.eks.cluster_security_group_id
  tags                          = var.tags
}

module "kms" {
  source = "./modules/kms"

  environment = var.environment
  tags        = var.tags
}

module "rds" {
  source = "./modules/rds"

  environment                   = var.environment
  db_name                       = "agora_${var.environment}"
  master_username               = var.db_master_username
  instance_class                = var.rds_instance_class
  serverless_min_capacity       = var.rds_serverless_min_capacity
  serverless_max_capacity       = var.rds_serverless_max_capacity
  reader_count                  = var.rds_reader_count
  allocated_storage             = var.rds_storage_gb
  vpc_id                        = module.vpc.vpc_id
  subnet_ids                    = module.vpc.database_subnets
  backup_retention_days         = var.rds_backup_retention_days
  multi_az                      = var.rds_multi_az
  engine_mode                   = "aurora-postgresql"
  kms_key_id                    = module.kms.key_arn
  eks_cluster_security_group_id = module.eks.cluster_security_group_id
  tags                          = var.tags
}

module "s3" {
  source = "./modules/s3"

  environment        = var.environment
  bucket_prefix      = "agora"
  versioning_enabled = true
  encryption_enabled = true
  kms_key_id         = module.kms.key_arn
  tags               = var.tags
}

module "monitoring" {
  source = "./modules/monitoring"

  environment              = var.environment
  alarm_notification_email = var.alarm_email
  sns_topic_prefix         = "agora-${var.environment}"
  amp_workspace_alias      = "agora-${var.environment}"
  tags                     = var.tags
}

module "iam" {
  source = "./modules/iam"

  environment                   = var.environment
  eks_oidc_issuer_url           = module.eks.oidc_issuer_url
  msk_cluster_arn               = module.msk.cluster_arn
  s3_data_lake_bucket_arn       = module.s3.data_lake_bucket_arn
  data_lake_consumer_account_id = var.data_lake_consumer_account_id
  tags                          = var.tags
}

module "kubernetes_addons" {
  source = "./modules/kubernetes-addons"

  environment                  = var.environment
  eks_cluster_name             = module.eks.cluster_name
  oidc_issuer_url              = module.eks.oidc_issuer_url
  vpc_id                       = module.vpc.vpc_id
  acme_email                   = var.acme_email
  ingress_load_balancer_scheme = var.ingress_load_balancer_scheme
  tags                         = var.tags

  depends_on = [
    module.eks,
    module.iam,
  ]
}
