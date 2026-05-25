# RDS (Aurora) Module
# Creates an Aurora PostgreSQL cluster with Multi-AZ, reader replicas, and Secrets Manager integration.

## What It Creates
- Aurora PostgreSQL cluster (Aurora Serverless v2 for dev, provisioned for staging/prod)
- Aurora writer instance + configurable reader replicas
- DB subnet group (isolated database subnets)
- Parameter group (force SSL, pg_stat_statements, logging)
- Security group (EKS nodes only)
- Secrets Manager secret (auto-rotating DB credentials)
- Enhanced monitoring IAM role
- CloudWatch log export (postgresql)

## Why Aurora PostgreSQL?
- ~30 second failover vs ~120 seconds for standard RDS
- Storage auto-scaling up to 128 TB
- Reader replicas for read scaling
- Performance Insights included

## Required Inputs
| Variable | Type | Description |
|----------|------|-------------|
| `db_name` | `string` | Database name |
| `master_username` | `string` | Master username |
| `master_password` | `string` | Master password (sensitive) |
| `instance_class` | `string` | Instance class |
| `vpc_id` | `string` | VPC ID |
| `subnet_ids` | `list(string)` | Database subnet IDs |
| `backup_retention_days` | `number` | Backup retention |

## Outputs
| Output | Description |
|--------|-------------|
| `cluster_endpoint` | Writer endpoint |
| `reader_endpoint` | Reader endpoint |
| `port` | Port (5432) |
| `database_name` | Database name |
| `master_username` | Master username |
| `secret_arn` | Secrets Manager ARN |

## Example
```hcl
module "rds" {
  source = "../modules/rds"

  environment         = "production"
  db_name            = "agora_production"
  master_username    = "agora_admin"
  master_password    = var.db_master_password
  instance_class     = "db.r6g.xlarge"
  reader_count       = 2
  vpc_id            = module.vpc.vpc_id
  subnet_ids        = module.vpc.database_subnets
  backup_retention  = 30
  multi_az          = true
}
```
