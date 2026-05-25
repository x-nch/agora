# IAM Module
# Creates IRSA roles for MSK IAM Access Control and cross-account S3 data lake access.

## What It Creates
- 6 IRSA roles for MSK IAM Access Control (traffic-optimizer, anomaly-detector, energy-optimizer, data-broker, kafka-connect, schema-registry)
- IRSA trust policies scoped to specific K8s ServiceAccounts in city-services namespace
- Cross-account IAM role and policy for S3 data lake access

## Required Inputs
| Variable | Type | Description |
|----------|------|-------------|
| `environment` | `string` | Environment name |
| `eks_oidc_issuer_url` | `string` | EKS OIDC issuer URL |
| `msk_cluster_arn` | `string` | MSK cluster ARN |
| `s3_data_lake_bucket_arn` | `string` | S3 data lake bucket ARN |

## Outputs
| Output | Description |
|--------|-------------|
| `msk_irsa_roles` | Map of service names to IAM role ARNs |
| `s3_data_lake_access_role_arn` | Cross-account data lake access role ARN |
| `s3_data_lake_access_policy_arn` | Data lake access policy ARN |

## No Secrets Required
MSK uses IAM Access Control (port 9098). Pods authenticate via IRSA — no Kafka username/password needed.

## Example
```hcl
module "iam" {
  source = "../modules/iam"

  environment            = "production"
  eks_oidc_issuer_url    = module.eks.oidc_issuer_url
  msk_cluster_arn        = module.msk.cluster_arn
  s3_data_lake_bucket_arn = module.s3.data_lake_bucket_arn
}
```
