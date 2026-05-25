# VPC Module
# Creates the network foundation for the Agora platform across 3 Availability Zones.

## What It Creates
- VPC with configurable CIDR
- Public, private, and database subnets across multiple AZs
- Internet Gateway + NAT Gateways (one per AZ)
- Route tables and associations
- VPC Gateway Endpoint for S3
- VPC Interface Endpoints for ECR, Secrets Manager, CloudWatch, AMP
- VPC Flow Logs (published to CloudWatch Logs)

## Required Inputs
| Variable | Type | Description |
|----------|------|-------------|
| `environment` | `string` | Environment name |
| `vpc_cidr` | `string` | VPC CIDR block |
| `availability_zones` | `list(string)` | AZ list |
| `public_subnet_cidrs` | `list(string)` | Public subnet CIDRs |
| `private_subnet_cidrs` | `list(string)` | Private subnet CIDRs |
| `database_subnet_cidrs` | `list(string)` | Database subnet CIDRs |

## Outputs
| Output | Description |
|--------|-------------|
| `vpc_id` | VPC ID |
| `public_subnets` | Public subnet IDs |
| `private_subnets` | Private subnet IDs |
| `database_subnets` | Database subnet IDs |
| `nat_gateway_ips` | NAT Gateway public IPs |

## Example
```hcl
module "vpc" {
  source = "../modules/vpc"

  environment         = "dev"
  vpc_cidr           = "10.0.0.0/16"
  availability_zones = ["ap-northeast-1a", "ap-northeast-1c"]
  public_subnet_cidrs   = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs  = ["10.0.11.0/24", "10.0.12.0/24"]
  database_subnet_cidrs = ["10.0.21.0/24", "10.0.22.0/24"]
}
```

## Common Errors
- **CIDR overlap**: Ensure subnet CIDRs are within the VPC CIDR and don't overlap
- **AZ mismatch**: Count of CIDRs must match count of AZs
- **NAT Gateway costs**: Each NAT Gateway costs ~$32/month + data processing
