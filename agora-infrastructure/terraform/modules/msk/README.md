# MSK Module
# Creates Amazon MSK cluster — Express for staging/production, Serverless for dev.

## What It Creates
- MSK Express cluster (staging/prod): 3 brokers, auto-scaling storage, IAM auth
- MSK Serverless cluster (dev): pay-per-use, no cluster management
- Security group (IAM auth port 9098, TLS port 9096, ZooKeeper 2181)
- Custom MSK configuration (auto.create.topics=false, 3x replication)
- CloudWatch log group for broker logs
- Enhanced monitoring (PER_TOPIC_PER_PARTITION)

## Why Express?
- 3x throughput per broker vs Standard
- 20x faster scaling (add brokers in minutes)
- 90% faster broker recovery
- Auto-scaling elastic storage (no EBS provisioning)

## Required Inputs
| Variable | Type | Description |
|----------|------|-------------|
| `broker_type` | `string` | "express" or "serverless" |
| `broker_node_count` | `number` | Broker count (Express only) |
| `instance_type` | `string` | Broker instance type |
| `vpc_id` | `string` | VPC ID |
| `subnet_ids` | `list(string)` | Subnet IDs (must span 3 AZs for Express) |
| `kafka_version` | `string` | Kafka version (Express requires 3.6+) |

## Outputs
| Output | Description |
|--------|-------------|
| `bootstrap_brokers_tls` | TLS bootstrap (port 9096) |
| `bootstrap_brokers_iam` | IAM bootstrap (port 9098) |
| `cluster_arn` | Cluster ARN |
| `security_group_id` | Security group ID |

## Example
```hcl
module "msk" {
  source = "../modules/msk"

  environment       = "production"
  broker_type       = "express"
  broker_node_count = 3
  instance_type     = "express.m7g.xlarge"
  vpc_id           = module.vpc.vpc_id
  subnet_ids       = module.vpc.private_subnets
  kafka_version    = "3.6"
}
```

## Common Errors
- **3 AZs required**: MSK Express requires subnets in exactly 3 Availability Zones
- **Port 9098**: IAM auth uses port 9098, not the default 9092
- **Kafka 3.6+**: Express requires Kafka version 3.6 or later
